#!/usr/bin/env bash
# encoding: utf-8
set -euo pipefail
FG_RED="$(tput setaf 1)"
TP_RESET="$(tput sgr0)"
MUSIC_RECOMMENDATIONS_ENV_FILEPATH="${MUSIC_RECOMMENDATIONS_ENV_FILEPATH:-"${XDG_CONFIG_HOME:-"${HOME}/.config"}/music_recommendations.env"}"
[ -f "$MUSIC_RECOMMENDATIONS_ENV_FILEPATH" ] && . "$MUSIC_RECOMMENDATIONS_ENV_FILEPATH"
MUSIC_HISTORY_JSON_FILEPATH="${MUSIC_HISTORY_JSON_FILEPATH:-"${HOME}/.shared_music_history.json"}"
SPOTIFY_CLIENT_INFO_FILEPATH="${SPOTIFY_CLIENT_INFO_FILEPATH:-"${HOME}/.config/.spotify.env"}"
[ -f "$SPOTIFY_CLIENT_INFO_FILEPATH" ] && . "$SPOTIFY_CLIENT_INFO_FILEPATH"
SPOTIFY_CLIENT_ID="${SPOTIFY_CLIENT_ID:-""}"
SPOTIFY_CLIENT_SECRET="${SPOTIFY_CLIENT_SECRET:-""}"

spotify_token_json_filepath() {
  printf '%s' "${HOME}/.spotify-token.json"
}

declare -A ERROR_CODES
ERROR_CODES["MISSING_URL"]="1,Missing URL argument"
ERROR_CODES["INVALID_URL"]="2,Invalid URL argument. Expected https:// or http://"
ERROR_CODES["INVALID_YOUTUBE_URL"]="3,Could not detect YouTube video ID in URL argument."
ERROR_CODES["MISSING_SPOTIFY_CLIENT_ID"]="4,SPOTIFY_CLIENT_ID is empty"
ERROR_CODES["MISSING_SPOTIFY_CLIENT_SECRET"]="4,SPOTIFY_CLIENT_SECRET is empty"
ERROR_CODES["SPOTIFY_INVALID_ACCESS_TOKEN"]="6,Spotify access token invalid: session expired?"
ERROR_CODES["SPOTIFY_TOKEN_REFRESH_FAILED"]="7,Failed to refresh Spotify Access Token"
ERROR_CODES["INVALID_SPOTIFY_TOKEN_JSON"]="8,Could not parse Spotify Access Token JSON file at $(spotify_token_json_filepath)"
ERROR_CODES["SPOTIFY_TRACK_RETRIEVAL_ERROR"]="9,Error while retrieving track JSON from Spotify: "
_error() {
  printf "${FG_RED}%s${TP_RESET}\n" "$@" 1>&2
}

error() {
  description="${2:-""}"
  usage="Usage: $(basename "$0") \$URL \"\$message\""
  _error "$(error_msg "$1")$description
$usage"
#  _error "exiting with $(error_code "$1")"
  exit $(error_code "$1")
  return "$1"
}

error_code() {
  printf '%s' "${ERROR_CODES["$1"]%%,*}"
}

error_msg() {
  printf '%s' "${ERROR_CODES["$1"]#*,}"
}

url="${1:-""}"
[ "$url" == "" ] && error MISSING_URL

[[ "$url" != https://* && "$url" != http://* ]] && error INVALID_URL

valid_spotify_token() {
  spotify_token_is_not_expired || refresh_spotify_token_json
  (( $? > 0 )) && error SPOTIFY_TOKEN_REFRESH_FAILED
  return 0
}
spotify_token() {
  jq -r '.access_token' "$(spotify_token_json_filepath)"
}
refresh_spotify_token_json() {
  [ "$SPOTIFY_CLIENT_ID" == "" ] && error MISSING_SPOTIFY_CLIENT_ID
  [ "$SPOTIFY_CLIENT_SECRET" == "" ] && error MISSING_SPOTIFY_CLIENT_SECRET
  curl -v -o "$(spotify_token_json_filepath)" -X "POST" -H "Authorization: Basic $(printf '%s:%s' "$SPOTIFY_CLIENT_ID" "$SPOTIFY_CLIENT_SECRET" | base64 -w 0)" -d grant_type=client_credentials https://accounts.spotify.com/api/token 1>&2
}

spotify_token_is_not_expired() {
  [ ! -f "$(spotify_token_json_filepath)" ] && return 255

  expires_in="$(jq -r '.expires_in' "$(spotify_token_json_filepath)")"
  (( $? > 0 )) && error INVALID_SPOTIFY_TOKEN_JSON
  (( ( ($(stat -c %Y "$(spotify_token_json_filepath)") + $expires_in) - $(date +"%s") ) > 0 )) && return 0 || return 255
}

spotify_get_track_json() {
  ! valid_spotify_token && exit $?
  local token="$(spotify_token)"
  #TODO: Cache the result
  result="$(curl --silent -X "GET" "https://api.spotify.com/v1/tracks/$1" -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $token")"
  json_error_status_code="$(printf '%s' "$result" | jq -r '.error .status//""' 2>/dev/null)"
  json_error_message="$(printf '%s' "$result" | jq -r '.error .message//""' 2>/dev/null)"
  [ "$json_error_status_code" == "401" ] && error SPOTIFY_UNAUTHORIZED
  [ "$json_error_message" != "" ] && error SPOTIFY_TRACK_RETRIEVAL_ERROR "${json_error_status_code}: ${json_error_message}"
  printf '%s' "$result"
}

title=""
html_type=""
if [[ "$url" == https://open.spotify.com/track/* ]]; then
  item_id="${url#https://open.spotify.com/track/}"

  title="$(spotify_get_track_json "$item_id" | jq -r '[(.artists | map(.name)| join(", ")), .name] | join(" — ")')" || exit $?
  message="${title} # ${description:-""}"
  html_type="spotify:track"
elif [[ "$url" == *youtube.com/* || "$url" == *youtu.be/* ]]; then
  item_id="$(printf '%s' "$url" | grep -oP '(https?://(www\.)?youtube\.com/watch/?(\?([^=]+=[^&]+)+&v=|\?v=)\K([^&])+|https?://(www\.)?youtu.be/\K([^/?&]+))')"
  [ "$item_id" == "" ] && error INVALID_YOUTUBE_URL
  title="$2"
  normalised_url="https://www.youtube.com/watch?v=${item_id}"
  message="$title"
  html_type="youtube:video"
else
  message="$2"
  html_type="unknown"
fi
description="${description:-"$2"}"

old_entries="$([ "$MUSIC_HISTORY_JSON_FILEPATH" != "" -a -f "$MUSIC_HISTORY_JSON_FILEPATH" ] && jq '.' "$MUSIC_HISTORY_JSON_FILEPATH" || echo "[]")"
jq -n \
  --arg url "$url" \
  --arg normalised_url "${normalised_url:-"$url"}" \
  --arg item_id "$item_id" \
  --arg title "$title" \
  --arg description "$description" \
  --arg message "$message" \
  --arg html_type "$html_type" \
  --argjson old_entries "$old_entries" \
  '[$old_entries, [{
    "url": $url,
    "normalised_url": $normalised_url,
    "item_id": $item_id,
    "title": $title,
    "description": $description,
    "message": $message,
    "html_type": $html_type
  }]] | add' | tee "$MUSIC_HISTORY_JSON_FILEPATH"

share_music_generate_output_files.sh

exit 0
