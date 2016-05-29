#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/config.sh"
DATA_DIR="${SCRIPT_DIR}/data"
POLY_DIR="${SCRIPT_DIR}/polygons"

echo 'Searching for the latest OSM file...'
GFB_DIRECTORY=https://download.geofabrik.de/${GFB_CONTINENT}/
GFB_HOUR=$( TZ=CET date '+%k' )
GFB_DATE=$( TZ=CET date '+%y%m%d' )
if (( $GFB_HOUR < 21 )) ; then # Before 21:00, files are still from yesterday, see https://download.geofabrik.de/technical.html
    GFB_DATE=$(( $GFB_DATE - 1 ))
fi
if [[ ! -f "${DATA_DIR}/${GFB_REGION}-${GFB_DATE}.osm.pbf" ]] ; then
    GFB_DATE=$( wget -q -O - "${GFB_DIRECTORY}" | sed -En 's/.*'"${GFB_REGION}"'-([0-9]{6})\.osm\.pbf.*/\1/p' | sort -r | head -1 )
fi
if [[ ! "$GFB_DATE" =~ ^[0-9]{6}$ ]] ; then
    echo "Invalid date \"${GFB_DATE}\" extracted from ${GFB_DIRECTORY}"
    exit 1
fi

cd "${DATA_DIR}"
echo 'Downloading OSM data...'
GFB_PBF_FILE=${GFB_REGION}-${GFB_DATE}.osm.pbf
GFB_MD5_FILE=${GFB_PBF_FILE}.md5
wget -qc --show-progress "https://download.geofabrik.de/${GFB_CONTINENT}/${GFB_PBF_FILE}"
wget -qc --show-progress "https://download.geofabrik.de/${GFB_CONTINENT}/${GFB_MD5_FILE}"
echo 'Verifying downloaded data...'
if ! md5sum --status -c "${GFB_MD5_FILE}" ; then
    echo "Invalid md5 sum: $( md5sum -c ${GFB_MD5_FILE} )"
    exit 1
fi

cd "${POLY_DIR}"
echo 'Downloading polygon file...'
wget -qc --show-progress "https://raw.githubusercontent.com/osmandapp/OsmAnd-misc/master/osm-planet/polygons/${OSA_REGION}.poly"

cd "${SCRIPT_DIR}"
echo 'Filtering out regional data...'
REGIONAL_PBF_FILE=${REGION}-${GFB_DATE}.osm.pbf
[[ -f "${DATA_DIR}/${REGIONAL_PBF_FILE}" ]] || "${OSMOSIS}" --read-pbf file="${DATA_DIR}/${GFB_PBF_FILE}" --bounding-polygon file="${POLY_DIR}/${REGION}.poly" --write-pbf "${DATA_DIR}/${REGIONAL_PBF_FILE}"

cd "${OSMAND_CREATOR_DIR}"
echo 'Converting to OsmAnd format...'
OSMAND_CREATOR_INPUT_DIR=$( sed -En 's/.*directory_for_osm_files="([^"]*)".*/\1/p' batch.xml )
if [[ ! -d "${OSMAND_CREATOR_INPUT_DIR}" ]] ; then
    echo "The path \"${OSMAND_CREATOR_INPUT_DIR}\" (directory_for_osm_files parameter in batch.xml) isn't a directory"
    exit 1
fi
cp "${DATA_DIR}/${REGIONAL_PBF_FILE}" "${OSMAND_CREATOR_INPUT_DIR}"
java -Djava.util.logging.config.file=logging.properties -Xms256M -Xmx2560M -cp "./OsmAndMapCreator.jar:./lib/OsmAnd-core.jar:./lib/*.jar" net.osmand.data.index.IndexBatchCreator ./batch.xml
