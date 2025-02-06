#!/usr/bin/env bash

${FLUTTER_STORAGE_BASE_URL:=https://storage.googleapis.com} > /dev/null 2>&1

latest_command() {
  DEFAULT_QUERY="[0-9]"

  local plugin_name=$1
  local query=$2
  local plugin_path

  if [ "$plugin_name" = "--all" ]; then
    latest_all
  fi

  [[ -z $query ]] && query="$DEFAULT_QUERY"

  plugin_path=$(get_plugin_path "$plugin_name")
  check_if_plugin_exists "$plugin_name"

  local versions

  if [ -f "${plugin_path}/bin/latest-stable" ]; then
    versions=$("${plugin_path}"/bin/latest-stable "$query")
    if [ -z "${versions}" ]; then
      # this branch requires this print to mimic the error from the list-all branch
      printf "No compatible versions available (%s %s)\n" "$plugin_name" "$query" >&2
      exit 1
    fi
  else
    # pattern from xxenv-latest (https://github.com/momo-lab/xxenv-latest)
    versions=$(list_all_command "$plugin_name" "$query" |
      grep -ivE "(^Available versions:|-src|-dev|-latest|-stm|[-\\.]rc|-milestone|-alpha|-beta|[-\\.]pre|-next|(a|b|c)[0-9]+|snapshot|master)" |
      sed 's/^[[:space:]]\+//' |
      tail -1)
    if [ -z "${versions}" ]; then
      exit 1
    fi
  fi

  printf "%s\n" "$versions"
}

latest_all() {
  local plugins_path
  plugins_path=$(get_plugin_path)

  if find "$plugins_path" -mindepth 1 -type d &>/dev/null; then
    for plugin_path in "$plugins_path"/*/; do
      plugin_name=$(basename "$plugin_path")

      # Retrieve the version of the plugin
      local version
      if [ -f "${plugin_path}/bin/latest-stable" ]; then
        # We can't filter by a concrete query because different plugins might
        # have different queries.
        version=$("${plugin_path}"/bin/latest-stable "")
        if [ -z "${version}" ]; then
          version="unknown"
        fi
      else
        # pattern from xxenv-latest (https://github.com/momo-lab/xxenv-latest)
        version=$(list_all_command "$plugin_name" |
          grep -ivE "(^Available version:|-src|-dev|-latest|-stm|[-\\.]rc|-alpha|-beta|[-\\.]pre|-next|(a|b|c)[0-9]+|snapshot|master)" |
          sed 's/^[[:space:]]\+//' |
          tail -1)
        if [ -z "${version}" ]; then
          version="unknown"
        fi
      fi

      local installed_status
      installed_status="missing"

      local installed_versions
      installed_versions=$(list_installed_versions "$plugin_name")

      if [ -n "$installed_versions" ] && printf '%s\n' "$installed_versions" | grep -q "^$version\$"; then
        installed_status="installed"
      fi
      printf "%s\t%s\t%s\n" "$plugin_name" "$version" "$installed_status"
    done
  else
    printf "%s\n" 'No plugins installed'
  fi
  exit 0
}

get_plugin_path() {
  if [ -n "$1" ]; then
    printf "%s\n" "$(asdf_data_dir)/plugins/$1"
  else
    printf "%s\n" "$(asdf_data_dir)/plugins"
  fi
}

asdf_data_dir() {
  local data_dir

  if [ -n "${ASDF_DATA_DIR}" ]; then
    data_dir="${ASDF_DATA_DIR}"
  elif [ -n "$HOME" ]; then
    data_dir="$HOME/.asdf"
  else
    data_dir=$(asdf_dir)
  fi

  printf "%s\n" "$data_dir"
}

asdf_dir() {
  if [ -z "$ASDF_DIR" ]; then
    local current_script_path=${BASH_SOURCE[0]}
    printf '%s\n' "$(
      cd -- "$(dirname "$(dirname "$current_script_path")")" || exit
      printf '%s\n' "$PWD"
    )"
  else
    printf '%s\n' "$ASDF_DIR"
  fi
}

list_all_command() {
  local plugin_name=$1
  local query=$2
  local plugin_path
  local std_out_file
  local std_err_file
  local output
  plugin_path=$(get_plugin_path "$plugin_name")
  check_if_plugin_exists "$plugin_name"

  local temp_dir
  temp_dir=${TMPDIR:-/tmp}

  # Capture return code to allow error handling
  std_out_file="$(mktemp "$temp_dir/asdf-command-list-all-${plugin_name}.stdout.XXXXXX")"
  std_err_file="$(mktemp "$temp_dir/asdf-command-list-all-${plugin_name}.stderr.XXXXXX")"
  return_code=0 && "${plugin_path}/bin/list-all" >"$std_out_file" 2>"$std_err_file" || return_code=$?

  if [[ $return_code -ne 0 ]]; then
    # Printing all output to allow plugin to handle error formatting
    printf "Plugin %s's list-all callback script failed with output:\n" "${plugin_name}" >&2
    printf "%s\n" "$(cat "$std_err_file")" >&2
    printf "%s\n" "$(cat "$std_out_file")" >&2
    rm "$std_out_file" "$std_err_file"
    exit 1
  fi

  if [[ $query ]]; then
    output=$(tr ' ' '\n' <"$std_out_file" |
      grep -E "^\\s*$query" |
      tr '\n' ' ')
  else
    output=$(cat "$std_out_file")
  fi

  if [ -z "$output" ]; then
    display_error "No compatible versions available ($plugin_name $query)"
    exit 1
  fi

  IFS=' ' read -r -a versions_list <<<"$output"

  for version in "${versions_list[@]}"; do
    printf "%s\n" "${version}"
  done

  # Remove temp files if they still exist
  rm "$std_out_file" "$std_err_file" || true
}

list_installed_versions() {
  local plugin_name=$1
  local plugin_path
  plugin_path=$(get_plugin_path "$plugin_name")

  local plugin_installs_path
  plugin_installs_path="$(asdf_data_dir)/installs/${plugin_name}"

  if [ -d "$plugin_installs_path" ]; then
    for install in "${plugin_installs_path}"/*/; do
      [[ -e "$install" ]] || break
      basename "$install" | sed 's/^ref-/ref:/'
    done
  fi
}

display_error() {
  printf "%s\n" "$1" >&2
}

check_if_plugin_exists() {
  local plugin_name=$1

  # Check if we have a non-empty argument
  if [ -z "${1}" ]; then
    display_error "No plugin given"
    exit 1
  fi

  if [ ! -d "$(asdf_data_dir)/plugins/$plugin_name" ]; then
    display_error "No such plugin: $plugin_name"
    exit 1
  fi
}