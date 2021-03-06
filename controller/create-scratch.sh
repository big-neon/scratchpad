#!/bin/bash
set -e

export timestamp=${timestamp:-$(date +'%Y-%m-%d_%Hh%M%S')}
exec &>> >(tee -a "logs/$(basename $0)-$timestamp.txt") 2>> >(tee -a "logs/$(basename $0)-$timestamp.err")

usage() {
    echo "API Branch required"
    echo "$0 --api api_branch_name [--name release_name_or_alias] [--web web_branch_name]"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

BASE_PATH="$(cd "$(dirname "$0")" && cd ../ && pwd)"
BASE_RELEASE_PATH="${BASE_PATH}/releases"
TEMPLATES_DIR="${BASE_PATH}/templates"
CONTROLLER_DIR="${BASE_PATH}/controller"
API_BRANCH=
while [ "$1" != "" ]; do
    case $1 in
    -a | --api)
        shift
        API_BRANCH=$1
        ;;
    -n | --name)
        shift
        RELEASE_NAME=$1
        ;;
    -w | --web)
        shift
        WEB_BRANCH=$1
        ;;
    -b | --build)
        shift
        BUILD_DIR=$1
        ;;
    -h | --help)
        usage
        exit
        ;;
    *)
        usage
        exit 1
        ;;
    esac
    shift
done

if [[ -z $API_BRANCH ]]; then
  usage
  exit 1
fi

RELEASE_NAME="${RELEASE_NAME:-$API_BRANCH}"
API_BRANCH_URL=${RELEASE_NAME//[^[:alnum:]-_]/}
WEB_BRANCH=${WEB_BRANCH:-master}
DB_NAME="bigneon_$API_BRANCH_URL"
RELEASE_PATH="${BASE_RELEASE_PATH}/$API_BRANCH_URL"
BUILD_DIR="${RELEASE_PATH}/${BUILD_DIR:-web}"

#The instance already exists, just pull the latest
if [ -d "$BUILD_DIR" ]; then
  cd "$RELEASE_PATH" && ./manage-instance.sh --update
  exit 0
fi

mkdir -p "$BUILD_DIR" || exit 1
mkdir -p "$RELEASE_PATH/logs" || exit 1
mkdir -p "$RELEASE_PATH/socks" || exit 1
touch "$RELEASE_PATH/logs/api.log" || exit 1
touch "$RELEASE_PATH/logs/web.log" || exit 1

chown -R "${CUID}:${CGID}" "$RELEASE_PATH"
chmod -R g+s "$RELEASE_PATH"

############################## Now we move into the release path
cd "${RELEASE_PATH}" || exit 1

LINK_FILES=("docker-compose.yml" "manage-instance.sh" "docker-compose.sh" "delete.sh")
for LINK_FILE in "${LINK_FILES[@]}"; do
  ln -sr "../../templates/$LINK_FILE" "./"
done

#Manually link the template fallback index.html
ln -sr "../../templates/building.html" "$BUILD_DIR/"
# Build the source file
cat << EOM > docker-source.sh
export HOST_RELEASE_PATH=$HOST_RELEASE_PATH
export RELEASE_NAME=$RELEASE_NAME
export BASE_RELEASE_PATH=$BASE_RELEASE_PATH
export RELEASE_PATH=$RELEASE_PATH
export BUILD_DIR=$BUILD_DIR
export API_BRANCH=$API_BRANCH
export API_BRANCH_URL=$API_BRANCH_URL
export WEB_BRANCH=$WEB_BRANCH
export DB_NAME=$DB_NAME
export CUID=$CUID
export CGID=$CGID
EOM
source docker-source.sh

GENERATE_ENVS=("web" "api" "bn-cube")
for GENERATE_ENV in "${GENERATE_ENVS[@]}"; do
  ./manage-instance.sh --reset-env "$GENERATE_ENV"
done

# Build the web
echo "Building the web ..."
./manage-instance.sh --web master --initialise --start

echo "Done."
