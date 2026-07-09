#!/usr/bin/with-contenv bashio

# ==============================================================================
# Cisco Vision SNMP2MQTT
# SNMP2MQTT bridge with optional Cisco Vision Discovery generated YAML import.
# ==============================================================================
if bashio::supervisor.ping; then
  bashio::log.blue \
    '-----------------------------------------------------------'
  bashio::log.blue " App: $(bashio::addon.name)"
  bashio::log.blue " $(bashio::addon.description)"
  bashio::log.blue \
    '-----------------------------------------------------------'
  bashio::log.blue " App version: $(bashio::addon.version)"
  if bashio::var.true "$(bashio::addon.update_available)"; then
    bashio::log.magenta ' There is an update available for this app!'
    bashio::log.magenta \
        " Latest app version: $(bashio::addon.version_latest)"
    bashio::log.magenta ' Please consider upgrading as soon as possible.'
  else
    bashio::log.green ' You are running the latest version of this app.'
  fi

  bashio::log.blue " System: $(bashio::info.operating_system)" \
    " ($(bashio::info.arch) / $(bashio::info.machine))"
  bashio::log.blue " Home Assistant Core: $(bashio::info.homeassistant)"
  bashio::log.blue " Home Assistant Supervisor: $(bashio::info.supervisor)"

  bashio::log.blue \
    '-----------------------------------------------------------'
  bashio::log.blue \
    ' Please share the above information when looking for help.'
  bashio::log.blue \
    '-----------------------------------------------------------'
fi

# ==============================================================================
CONFIG_PATH=/data/options.json
TARGET_PATH="$(bashio::config 'targets_path')"
USE_CISCO_VISION_GENERATED_YAML="$(bashio::config 'use_cisco_vision_generated_yaml')"
CISCO_VISION_GENERATED_YAML_PATH="$(bashio::config 'cisco_vision_generated_yaml_path')"
IMPORTED_TARGETS_PATH="$(bashio::config 'imported_targets_path')"
BACKUP_EXISTING_CONFIG="$(bashio::config 'backup_existing_config')"

if [ -z "${TARGET_PATH}" ]; then
  TARGET_PATH="/config/addons_config/cisco_vision_snmp2mqtt/targets.yaml"
  bashio::log.notice 'Switch to default file with Targets:'
  bashio::log.notice " ${TARGET_PATH}"
fi

if [ -z "${CISCO_VISION_GENERATED_YAML_PATH}" ]; then
  CISCO_VISION_GENERATED_YAML_PATH="/share/cisco_vision/generated-snmp2mqtt.yaml"
fi

if [ -z "${IMPORTED_TARGETS_PATH}" ]; then
  IMPORTED_TARGETS_PATH="/config/addons_config/cisco_vision_snmp2mqtt/imported/generated-snmp2mqtt.yaml"
fi

validate_cisco_vision_generated_yaml() {
  local generated_file="$1"

  if [ ! -f "${generated_file}" ]; then
    bashio::log.fatal 'Cisco Vision generated YAML import is enabled, but file was not found:'
    bashio::log.fatal " ${generated_file}"
    return 1
  fi

  if grep -q 'CHANGE_ME' "${generated_file}"; then
    bashio::log.fatal 'Cisco Vision generated YAML rejected: CHANGE_ME placeholder found.'
    return 1
  fi

  if ! grep -q '^# Cisco Vision generated SNMP2MQTT YAML' "${generated_file}"; then
    bashio::log.fatal 'Cisco Vision generated YAML rejected: generated YAML header missing.'
    return 1
  fi

  if ! grep -q '^# Source: Cisco Vision Discovery' "${generated_file}"; then
    bashio::log.fatal 'Cisco Vision generated YAML rejected: Cisco Vision Discovery source header missing.'
    return 1
  fi

  if ! grep -q '^targets:' "${generated_file}"; then
    bashio::log.fatal 'Cisco Vision generated YAML rejected: targets block missing.'
    return 1
  fi

  if ! grep -Eq '^[[:space:]]*-[[:space:]]+host:[[:space:]]+[^[:space:]]+' "${generated_file}"; then
    bashio::log.fatal 'Cisco Vision generated YAML rejected: no target host entries found.'
    return 1
  fi

  return 0
}

if bashio::var.true "${USE_CISCO_VISION_GENERATED_YAML}"; then
  bashio::log.info 'Cisco Vision generated YAML import is enabled.'
  bashio::log.info 'Cisco Vision generated YAML path:'
  bashio::log.blue "                  ${CISCO_VISION_GENERATED_YAML_PATH}"

  if ! validate_cisco_vision_generated_yaml "${CISCO_VISION_GENERATED_YAML_PATH}"; then
    bashio::exit.nok
  fi

  mkdir -p "$(dirname "${IMPORTED_TARGETS_PATH}")"

  if bashio::var.true "${BACKUP_EXISTING_CONFIG}" && [ -f "${TARGET_PATH}" ]; then
    BACKUP_DIR="/config/addons_config/cisco_vision_snmp2mqtt/backups"
    BACKUP_FILE="${BACKUP_DIR}/targets-$(date -u +%Y%m%dT%H%M%SZ).yaml"
    mkdir -p "${BACKUP_DIR}"
    cp "${TARGET_PATH}" "${BACKUP_FILE}"
    bashio::log.info 'Existing SNMP2MQTT targets config backed up to:'
    bashio::log.blue "                  ${BACKUP_FILE}"
  fi

  cp "${CISCO_VISION_GENERATED_YAML_PATH}" "${IMPORTED_TARGETS_PATH}"
  TARGET_PATH="${IMPORTED_TARGETS_PATH}"

  bashio::log.info 'Cisco Vision generated YAML validated and imported to:'
  bashio::log.blue "                  ${TARGET_PATH}"
else
  bashio::log.info 'Cisco Vision generated YAML import is disabled.'
fi

if [ ! -f "${TARGET_PATH}" ]; then
  bashio::log.fatal
  bashio::log.fatal 'Configuration of this app is incomplete.'
  bashio::log.fatal
  bashio::log.fatal 'File with Targets config not found:'
  bashio::log.fatal " ${TARGET_PATH}"
  bashio::log.fatal
  bashio::exit.nok
fi

bashio::log.info 'SNMP2MQTT Starting...'

bashio::log.info 'Prepare config...'
yq -p json -o yaml \
  'del(.targets_path, .use_cisco_vision_generated_yaml, .cisco_vision_generated_yaml_path, .imported_targets_path, .backup_existing_config)' \
  "${CONFIG_PATH}" > /app/config.yml
cat "${TARGET_PATH}" >> /app/config.yml

bashio::log.info
bashio::log.info 'Configuration - Targets from:'
bashio::log.blue "                  ${TARGET_PATH}"
bashio::log.info 'Configuration - MQTT Host:'
bashio::log.blue "                  $(bashio::config 'mqtt.host')"
bashio::log.info 'SNMP2MQTT Start'
bashio::log.info

# ==============================================================================
bashio::color.blue
node /app/dist/index.js
bashio::color.reset

# ==============================================================================
bashio::log.info
bashio::log.info 'SNMP2MQTT Stop'
bashio::exit.ok
