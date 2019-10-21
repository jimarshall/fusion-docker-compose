#!/bin/bash

CALLED=$_

# check if script has been sourced, and if not, output for parsing by eval $(<setup-env.sh)
IS_SOURCED=1
if [ "$0" = "$BASH_SOURCE" -o "$0" = "$CALLED" ]; then
  IS_SOURCED=0
fi

# this script uses relative paths, this cd is more complex with a sourced script
if [ $IS_SOURCED = 1 ]; then
  if [ -n "$BASH_SOURCE" ]; then
    cd "$(dirname $BASH_SOURCE)"
  else
    cd "$(dirname $CALLED)"
  fi
else
  cd "$(dirname $0)"
fi

opt_f="compose.env"
opt_h=0
opt_u=0

# functions
usage() {
  echo "Usage: $0 [opts]"
  echo " -f file: main env file to use (default: ${opt_f})"
  echo " -h: this help message"
  echo " -u: update settings"
  [ "$opt_h" = "1" ] && exit 0 || exit 1
}

load_file() {
  filename="$1"

  while IFS="=" read -r key value; do
    eval "$key=\"$value\""
  done <"$filename"
}

generate_compose_var() {
  (
    . "./${COMMON_ENV}"
    printf "%s:%s" "${COMPOSE_FILE_COMMON_OUT}" "${COMPOSE_FILE_A_OUT}"
    if [ "$ZONE_B_TYPE" = NONE ]; then
      printf "\n"
      exit 0
    fi
    printf ":%s\n" "${COMPOSE_FILE_B_OUT}"
  )
}

save_var() {
  var="$1"
  new_val="$2"
  filename="$3"

  # check for current version
  cur_val=$([ -f "${filename}" ] && grep "^${var}=" "${filename}" | cut -f2- -d= )

  # if aleady on the right version, return
  if [ "${new_val}" = "${cur_val}" ]; then
    return
  fi

  if [ -n "${cur_val}" ]; then
    # if already set, modify
    sed_safe_val="$(echo "${new_val}" | sed -e 's/[\/&]/\\&/g')"
    sed -i "s/^${var}=.*\$/${var}=${sed_safe_val}/" "${filename}"
  else
    # else append a value to the file
    echo "${var}=${new_val}" >> "${filename}"
  fi
  eval "$var=\"$new_val\""
}

update_var() {
  var_name=$1
  var_msg=$2
  default=$3
  validate=$4
  # get the value for $var_name
  var_val=$(eval echo -n \"\$$var_name\")
  # make the existing value the default
  [ -n "${var_val}" ] && default="${var_val}"
  # include the current/default in the prompt
  [ -n "${default}" ] && default_msg=" [${default}]" || default_msg=""
  # prompt the user if a value isn't already defined or override is set
  if [ -z "${var_val}" -o "$opt_u" = "1" ]; then
    read -p "${var_msg}${default_msg}: " ${var_name}
  fi
  var_val=$(eval echo -n \"\$$var_name\")
  # set the value to the default if an empty string entered
  if [ -z "${var_val}" -a -n "${default}" ]; then
    var_val="${default}"
    eval "${var_name}=\"${default}\""
  fi
  # validate the input, rerun the prompt on validation failure
  while [ -n "${validate}" ] && ! eval "${validate}" "${var_val}"; do
    read -p "${var_msg}: " ${var_name}
    var_val=$(eval echo -n \"\$$var_name\")
  done
  if [ -n "${SAVE_ENV}" ]; then
    save_var "${var_name}" "${var_val}" "${SAVE_ENV}"
  fi
  export "$var_name"
  return 0
}

validate_not_empty() {
  value="$1"
  if [ -z "$value" ]; then
    echo "Error: value cannot be empty"
    return 1
  fi
  return 0
}

validate_not_example() {
  value="$1"
  case "$value" in
    ''|*example*)
      echo "Error: example or empty value is not valid"
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

validate_number() {
  value="$1"
  case "$value" in
    ''|*[!0-9]*)
      echo "Error: value must be a number"
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

validate_file_path() {
  value="$1"
  if [ $value ] && [ ! -f $value ]; then
    echo "Error: File path must exist"
    return 1
  fi
  return 0
}

validate_zone_name() {
  zone_name=$1
  if [ -z "$zone_name" ] || echo "$zone_name" | egrep -q '[^a-z0-9\-]'; then
    echo "Zone name must only contain lower case letters, numbers, or -, no spaces or other characters"
    return 1
  fi
  return 0
}

validate_zone_type() {
  zone_type=$1

  if [ "$zone_type" = "NONE" -o -f "zone-${zone_type}.conf" ]; then
    return 0
  else
    echo "Please choose from one of the following zone types:"
    echo
    for zone in zone-*.conf; do
      zone_type=${zone#zone-}
      echo "  ${zone_type%.conf}"
    done
    echo
    return 1
  fi
}

# parse CLI
while getopts 'f:hu' option; do
  case $option in
    f) opt_f="$OPTARG";;
    h) opt_h=1;;
    u) opt_u=1;;
  esac
done
set +e
shift `expr $OPTIND - 1`

if [ $# -gt 0 -o "$opt_h" = "1" ]; then
  usage
fi

# load the cached env
[ -f "./$opt_f" ] && load_file "./$opt_f"

# set default values for variables that could be overridden in compose env
: "${COMMON_ENV:=common.env}"
: "${ZONE_A_ENV:=zone_a.env}"
: "${ZONE_B_ENV:=zone_b.env}"
: "${COMPOSE_FILE_A_OUT:=docker-compose.zone-a.yml}"
: "${COMPOSE_FILE_B_OUT:=docker-compose.zone-b.yml}"
: "${COMPOSE_FILE_COMMON_OUT:=docker-compose.common.yml}"

set -a
FUSION_BASE_VERSION=2.14.1.3
FUSION_IMAGE_RELEASE=1
FUSION_NN_PROXY_VERSION="4.0.0.3"
FUSION_NN_PROXY_IMAGE_RELEASE=1
FUSION_ONEUI_VERSION=2.14.1.0
set +a

# run everything below in a subshell to avoid leaking env vars
(
  SAVE_ENV=${COMMON_ENV}

  # update settings when not defined or force update specified

  ## load existing common variables
  [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"

  ## set variables for compose zone a

  validate_zone_type "$ZONE_A_TYPE"
  update_var ZONE_A_TYPE "Enter the first zone type" "Press enter for a list" validate_zone_type
  update_var ZONE_A_NAME "Enter a name for the first zone" "$ZONE_A_TYPE" validate_zone_name

  ## set variables for compose zone b
  while :; do
    [ -n "$ZONE_B_TYPE" ] && break
    read -p "Configure a second zone? (Y/n) " REPLY
    case ${REPLY:-y} in
      Y|y) break ;;
      N|n) ZONE_B_TYPE=NONE; break ;;
    esac
  done

  update_var ZONE_B_TYPE "Enter the second zone type" "Press enter for a list" validate_zone_type
  if [ "$ZONE_B_TYPE" != NONE ]; then
    update_var ZONE_B_NAME "Enter a name for the second zone" "$ZONE_B_TYPE" validate_zone_name
  fi

  ## setup common file
  export ZONE_A_ENV ZONE_B_ENV ZONE_A_NAME ZONE_B_NAME
  # run the common conf
  . "./common.conf"

  if [ ${LICENSE_FILE} ]; then
    export LICENSE_FILE_PATH="- ${LICENSE_FILE}:/etc/wandisco/fusion/server/license.key"
  fi

  ## run zone a setup (use a subshell to avoid leaking env vars)
  (
    default_port_offset=0
    zone_letter=A
    set -a
    SAVE_ENV=${ZONE_A_ENV}
    ZONE_ENV=${ZONE_A_ENV}
    ZONE_NAME=${ZONE_A_NAME}
    ZONE_TYPE=${ZONE_A_TYPE}
    # set common fusion variables
    FUSION_NODE_ID=${ZONE_A_NODE_ID}
    # save common vars to zone file
    save_var ZONE_NAME "$ZONE_NAME" "$SAVE_ENV"
    save_var FUSION_NODE_ID "$FUSION_NODE_ID" "$SAVE_ENV"
    # load any existing zone environment
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    # run the common fusion zone config
    . "./common-fusion.conf"
    # run the zone type config
    . "./zone-${ZONE_TYPE}.conf"
    # re-load variables
    load_file "./${ZONE_ENV}"
    envsubst <"docker-compose.zone-tmpl-${ZONE_TYPE}.yml" >"${COMPOSE_FILE_A_OUT}"
    set +a
  )

  ## run zone b setup (use a subshell to avoid leaking env vars)
  (
    [ $ZONE_B_TYPE = NONE ] && exit 0
    default_port_offset=500
    zone_letter=B
    set -a
    SAVE_ENV=${ZONE_B_ENV}
    ZONE_ENV=${ZONE_B_ENV}
    ZONE_NAME=${ZONE_B_NAME}
    ZONE_TYPE=${ZONE_B_TYPE}
    # set common fusion variables
    FUSION_NODE_ID=${ZONE_B_NODE_ID}
    # save common vars to zone file
    save_var ZONE_NAME "$ZONE_NAME" "$SAVE_ENV"
    save_var FUSION_NODE_ID "$FUSION_NODE_ID" "$SAVE_ENV"
    # load any existing zone environment
    [ -f "${ZONE_ENV}" ] && load_file "./${ZONE_ENV}"
    # run the common fusion zone config
    . "./common-fusion.conf"
    # run the zone type config
    . "./zone-${ZONE_TYPE}.conf"
    # re-load variables
    load_file "./${ZONE_ENV}"
    envsubst <"docker-compose.zone-tmpl-${ZONE_TYPE}.yml" >"${COMPOSE_FILE_B_OUT}"
    set +a
  )

  ## generate the common yml
  (
    set -a
    # load env files in order of increasing priority
    [ -f "${ZONE_B_ENV}" ] && load_file "./${ZONE_B_ENV}"
    [ -f "${ZONE_A_ENV}" ] && load_file "./${ZONE_A_ENV}"
    [ -f "./${COMMON_ENV}" ] && load_file "./${COMMON_ENV}"
    envsubst <"docker-compose.common-tmpl.yml" >"${COMPOSE_FILE_COMMON_OUT}"
    set +a
  )

)

# export common compose file variables
export COMPOSE_FILE=$(generate_compose_var)

if [ "$IS_SOURCED" = "0" ]; then
  echo "# This script should be sourced with:"
  echo "#   . $0"
  echo "# Or you can manually export the following:"
  echo "export COMPOSE_FILE=\"${COMPOSE_FILE}\""
  echo "Run docker-compose up -d to start the Fusion containers"
  echo "Once Fusion starts browse to http://HOST:8080 to access the UI"
fi