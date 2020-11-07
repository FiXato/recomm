#!/usr/bin/env bash
# encoding: utf-8
FG_RED="$(tput setaf 1)"
TP_RESET="$(tput sgr0)"
MUSIC_RECOMMENDATIONS_ENV_FILEPATH="${MUSIC_RECOMMENDATIONS_ENV_FILEPATH:-"${XDG_CONFIG_HOME:-"${HOME}/.config"}/music_recommendations.env"}"
[ -f "$MUSIC_RECOMMENDATIONS_ENV_FILEPATH" ] && source "$MUSIC_RECOMMENDATIONS_ENV_FILEPATH"
OUTPUT_TEXT_FILEPATH="${OUTPUT_TEXT_FILEPATH:-/var/www/html/music/recommendations.txt}"
OUTPUT_HTML_FILEPATH="${OUTPUT_HTML_FILEPATH:-"${OUTPUT_TEXT_FILEPATH/.txt/.html}"}"
MUSIC_HISTORY_JSON_FILEPATH="${MUSIC_HISTORY_JSON_FILEPATH:-"${HOME}/.shared_music_history.json"}"
AUTHOR_NAME_HTML="${AUTHOR_NAME_HTML:-"A user who &lsquo;forgot&rsquo; to edit the AUTHOR_NAME_HTML env-var in their MUSIC_RECOMMENDATIONS_ENV file."}"
MUSIC_RECOMMENDATIONS_PAGE_TITLE_HTML="${MUSIC_RECOMMENDATIONS_PAGE_TITLE_HTML-"My music recommendations"}"
MUSIC_RECOMMENDATIONS_BASE_URL="${MUSIC_RECOMMENDATIONS_BASE_URL:-"https://I.forgot.to.edit.MUSIC_RECOMMENDATIONS_BASE_URL.in.my.ENV.file.example"}"

declare -A ERROR_CODES
ERROR_CODES["MISSING_JSON_INPUT_FILE"]="1,Could not find input JSON file: "

_error() {
  printf "${FG_RED}%s${TP_RESET}\n" "$@" 1>&2
}

error() {
  _error "$(error_msg "$1")$2"
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

[ "$MUSIC_HISTORY_JSON_FILEPATH" == "" -o ! -f "$MUSIC_HISTORY_JSON_FILEPATH" ] && error MISSING_JSON_INPUT_FILE "$MUSIC_HISTORY_JSON_FILEPATH"

tee "$OUTPUT_HTML_FILEPATH" <<EOTEMPLATE
<!doctype html>
<html lang="en" prefix="og: http://ogp.me/ns#">
  <head>
    <!-- Required meta tags -->
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <meta name="description" content="Music recommendations by $AUTHOR_NAME_HTML. Watch embedded YouTube music videos, or listen to embedded Spotify tracks here.">
    <meta property="og:description" content="Music recommendations by $AUTHOR_NAME_HTML. Watch embedded YouTube music videos, or listen to embedded Spotify tracks here.">
    <meta property="og:url" content="$MUSIC_RECOMMENDATIONS_BASE_URL/recommendations.html">
    <meta property="og:image" content="melody.jpg">
    <!-- Bootstrap CSS -->
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css" integrity="sha384-ggOyR0iXCbMQv3Xipma34MD+dH/1fQ784/j6cY/iJTQUOhcWr7x9JvoRxT2MZw1T" crossorigin="anonymous">
    <style type="text/css">
      .embed-container {
        position: relative;
        padding-bottom: 56.25%;
        height: 0;
        overflow: hidden;
        max-width: 100%;
      }
      .embed-container iframe, .embed-container object, .embed-container embed {
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
      }
      p.title {max-height: 3.5em; overflow: hidden; text-overflow: ellipsis; padding: 0.75rem; padding-bottom: 0;}
      p.title a {text-overflow: ellipsis}
      p.description {
        height: 7em;
        overflow: auto;
        margin-bottom: 0;
        white-space: pre-wrap;
        font-size: 0.9em;
      }
      .card {
        margin-bottom: 1.75rem;
      }
      .card-body {
        padding: 0.75rem;
      }
      .jumbotron {
        margin-top: 0.75rem;
      }
      .spotify_track .card-img-top, .spotify_track .embed-container, .spotify_track .embed-container iframe {
        height: 80px;
      }
      .spotify_track .embed-container {
        padding-bottom: unset;
      }
      footer#footer {
        margin-bottom: 1em;
        text-align: center;
        background: rgba(0,0,0,0.5);
        padding: 0.5em;
      }
    </style>
    <link rel="stylesheet" href="$MUSIC_RECOMMENDATIONS_STYLESHEET">
    <title>$MUSIC_RECOMMENDATIONS_PAGE_TITLE_HTML</title>
    <meta property="og:title" content="$MUSIC_RECOMMENDATIONS_PAGE_TITLE_HTML" />
  </head>
  <body itemscope itemtype="http://schema.org/Product">
    <div class="container-fluid">
      <div class="row">
        <div class="col-sm-12">
          <div class="jumbotron">
            <div class="row">
              <div class="col-sm-12 col-md-6">
                <h1 itemprop="name">$MUSIC_RECOMMENDATIONS_PAGE_TITLE_HTML</h1>
                <p itemprop="description">A bunch of tracks I've recently listened to and decided to explicitly share here. I try to keep it diverse, though occasionally I might share multiple songs of the same artist in a row.</p>
              </div>
              <div class="d-sm-none d-md-block col-md-6">
                <p><img itemprop="image" src="melody.jpg" alt="Melody logo" /></p>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="row">
EOTEMPLATE

declare -a item_types=("spotify:track" "youtube:video")
for html_type in "${item_types[@]}"
do
  item_count="$(jq -r --arg html_type "$html_type" '[.[]|select(.html_type == $html_type)] | length' "$MUSIC_HISTORY_JSON_FILEPATH")"
  tee -a "$OUTPUT_HTML_FILEPATH" <<EOTEMPLATE
        <div class="col-sm-12 col-md-$([ "$html_type" == "youtube:video" ] && printf '5' || printf '7')">
          <h2>$([ "$html_type" == "spotify:track" ] && printf '%s' 'Spotify Tracks')$([ "$html_type" == "youtube:video" ] && printf '%s' 'YouTube Videos')</h2>
          <div class="row">
EOTEMPLATE

  for ((i=0; i<$item_count; i++))
  do
    item_json="$(jq --arg i "$i" --arg html_type "$html_type" '[reverse|.[]|select(.html_type == $html_type)][$i|tonumber]' "$MUSIC_HISTORY_JSON_FILEPATH")"
    url="$(printf '%s' "$item_json" | jq -r '.url')"
    normalised_url="$(printf '%s' "$item_json" | jq -r '.normalised_url')"
    item_id="$(printf '%s' "$item_json" | jq -r '.item_id')"
    title="$(printf '%s' "$item_json" | jq -r '.title')"
    description="$(printf '%s' "$item_json" | jq -r '.description')"
    message="$(printf '%s' "$item_json" | jq -r '.message')"

    [ "$html_type" == "youtube:video" ] && iframe_src="https://www.youtube.com/embed/${item_id}" && iframe_dimensions=''
    [ "$html_type" == "spotify:track" ] && iframe_src="https://open.spotify.com/embed/track/${item_id}" && iframe_dimensions="width='100%' height='80px'"
    media_type="${html_type//:/_}"
    description="${description:-"$title"}"
    tee -a "$OUTPUT_HTML_FILEPATH" <<EOTEMPLATE
              <div class="col-sm-12 col-lg-$([ "$html_type" == "youtube:video" ] && printf '12' || printf '6') ${media_type}">
                <div class="card" itemprop="review" itemscope itemtype="http://schema.org/Review">
                    <p class="title" itemprop="name">
                      <a href="${url}" itemprop="itemReviewed">${title}</a>
                    </p>
                  <label class="d-none">Reviewed by:</label><span class="d-none" itemprop="author">FiXato</span>
                  <div class="card-img-top">
                    $([ "$iframe_src" != "" ] && printf '%s' "<div class='embed-container'><iframe src='${iframe_src}' class='media ${media_type}' $iframe_dimensions frameborder='0' allowtransparency='true' allow='encrypted-media' webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe></div>")
                  </div>
                  <div class="card-body">
                    <p class="description" itemprop="reviewBody">${description}</p>
                  </div>
                </div>
              </div>
EOTEMPLATE

    printf '%s\n' "${url}: $message" | tee -a "$OUTPUT_TEXT_FILEPATH"
  done
  tee -a "$OUTPUT_HTML_FILEPATH" <<'EOTEMPLATE'
            </div>
          </div>
EOTEMPLATE
done

tee -a "$OUTPUT_HTML_FILEPATH" <<'EOTEMPLATE'
        </div>
      </div>
    </div>
    <footer id="footer">A project by <a href="https://contact.fixato.org/">FiXato</a>. Want to contribute? Find the <a href="https://github.com/FiXato/recomm">code on Github</a>, or <a href="https://www.paypal.me/FiXato">donate on PayPal</a>.</footer>
  </body>
</html>
EOTEMPLATE
