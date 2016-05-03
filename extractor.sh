#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/config.sh"
DATA_DIR="${SCRIPT_DIR}/data"
POLY_DIR="${SCRIPT_DIR}/polygons"

# TODO Do not fetch the date if a pbf file already exist for the date of today
echo 'Searching for the latest OSM file...'
GFB_DIRECTORY=https://download.geofabrik.de/${GFB_CONTINENT}/
GFB_DATE=$( wget -q -O - "${GFB_DIRECTORY}" | sed -En 's/.*china-([0-9]{6})\.osm\.pbf.*/\1/p' | sort -r | head -1 )
if ! [[ "$GFB_DATE" =~ ^[0-9]{6}$ ]] ; then
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
"${OSMOSIS}" --read-pbf file="${DATA_DIR}/${GFB_PBF_FILE}" --bounding-polygon file="${POLY_DIR}/${REGION}.poly" --write-pbf "${DATA_DIR}/${REGIONAL_PBF_FILE}"

cd "${OSA_CREATOR_BIN_DIR}"
echo 'Converting to OsmAnd format...'
cp "${DATA_DIR}/${REGIONAL_PBF_FILE}" "${OSA_CREATOR_PBF_DIR}"
java -Djava.util.logging.config.file=logging.properties -Xms256M -Xmx2560M -cp "./OsmAndMapCreator.jar:./lib/OsmAnd-core.jar:./lib/*.jar" net.osmand.data.index.IndexBatchCreator ./batch.xml
