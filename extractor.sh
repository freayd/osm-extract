#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DATA_DIR="${SCRIPT_DIR}/data"
mkdir -p "${DATA_DIR}"

echo 'Searching for the latest OSM file...'
GFB_TOP_REGION=$( dirname ${GFB_REGION} )
GFB_SUB_REGION=$( basename ${GFB_REGION} )
GFB_DIRECTORY=https://download.geofabrik.de/${GFB_TOP_REGION}/
GFB_HOUR=$( TZ=CET date '+%k' )
GFB_DATE=$( TZ=CET date '+%y%m%d' )
if (( $GFB_HOUR < 21 )) ; then # Before 21:00, files are still from yesterday, see https://download.geofabrik.de/technical.html
    GFB_DATE=$(( $GFB_DATE - 1 ))
fi
if [[ ! -f "${DATA_DIR}/${GFB_SUB_REGION}-${GFB_DATE}.osm.pbf" ]] ; then
    GFB_DATE=$( wget -q -O - "${GFB_DIRECTORY}" | sed -En 's/.*'"${GFB_SUB_REGION}"'-([0-9]{6})\.osm\.pbf.*/\1/p' | sort -r | head -1 )
fi
if [[ ! "$GFB_DATE" =~ ^[0-9]{6}$ ]] ; then
    echo "Invalid date \"${GFB_DATE}\" extracted from ${GFB_DIRECTORY}"
    exit 1
fi

cd "${DATA_DIR}"
echo 'Downloading OSM data...'
GFB_PBF_FILE=${GFB_SUB_REGION}-${GFB_DATE}.osm.pbf
GFB_MD5_FILE=${GFB_PBF_FILE}.md5
wget -qc --show-progress "https://download.geofabrik.de/${GFB_TOP_REGION}/${GFB_PBF_FILE}"
wget -qc --show-progress "https://download.geofabrik.de/${GFB_TOP_REGION}/${GFB_MD5_FILE}"
echo 'Verifying downloaded data...'
if ! md5sum --status -c "${GFB_MD5_FILE}" ; then
    echo "Invalid md5 sum: $( md5sum -c ${GFB_MD5_FILE} )"
    exit 1
fi

REGION=$( basename "${BASH_SOURCE[1]}" .sh )
REGIONAL_PBF_FILE=${REGION}-${GFB_DATE}.osm.pbf
REGIONAL_OBF_FILE=${REGION}-${GFB_DATE}.obf
OSMOSIS="${SCRIPT_DIR}/osmosis/package/bin/osmosis"
OSMAND_POLY_DIR="${SCRIPT_DIR}/osmand/misc/osm-planet/polygons"
if ! "${OSMOSIS}" -v &> /dev/null ; then
    echo 'Compiling Osmosis...'
    cd "${SCRIPT_DIR}/osmosis"
    ./gradlew assemble || exit 1
fi
if [[ ! -f "${DATA_DIR}/${REGIONAL_PBF_FILE}" ]] ; then
    echo 'Filtering out regional data...'
    "${OSMOSIS}" --read-pbf file="${DATA_DIR}/${GFB_PBF_FILE}" --bounding-polygon file="${OSMAND_POLY_DIR}/${OSA_POLYGON}" --write-pbf "${DATA_DIR}/${REGIONAL_PBF_FILE}"
fi

OSMAND_CREATOR_DIR="${SCRIPT_DIR}/osmand/tools/OsmAndMapCreator"
OSMAND_CREATOR_BATCH="${SCRIPT_DIR}/osmand/creator-batch.xml"
OSMAND_CREATOR_TMP_DIR="${SCRIPT_DIR}/osmand/.creator"
OSMAND_CREATOR_PBF_DIR="${SCRIPT_DIR}/osmand/.creator/pbf"
OSMAND_CREATOR_OBF_DIR="${SCRIPT_DIR}/osmand/.creator/obf"
mkdir -p "${OSMAND_CREATOR_TMP_DIR}"
mkdir -p "${OSMAND_CREATOR_PBF_DIR}"
mkdir -p "${OSMAND_CREATOR_OBF_DIR}"
rm -f "${OSMAND_CREATOR_TMP_DIR}/"*.obf.*
rm -f "${OSMAND_CREATOR_TMP_DIR}/"*.odb
rm -f "${OSMAND_CREATOR_PBF_DIR}/"*.pbf
rm -f "${OSMAND_CREATOR_OBF_DIR}/"*.obf
cd "${OSMAND_CREATOR_DIR}"
if [[ ! -f "${OSMAND_CREATOR_DIR}/OsmAndMapCreator.jar" ]] ; then
    echo 'Compiling OsmAndMapCreator...'
    ant jar || exit 1
fi
if [[ ! -f "${DATA_DIR}/${REGIONAL_OBF_FILE}" ]] ; then
    echo 'Converting to OsmAnd format...'
    ln -s "${DATA_DIR}/${REGIONAL_PBF_FILE}" "${OSMAND_CREATOR_PBF_DIR}"
    java -Djava.util.logging.config.file=logging.properties -Xms256M -Xmx2560M -cp "./OsmAndMapCreator.jar:./lib/OsmAnd-core.jar:./lib/*.jar" net.osmand.data.index.IndexBatchCreator "${OSMAND_CREATOR_BATCH}"
    mv "${OSMAND_CREATOR_OBF_DIR}/"*.obf "${DATA_DIR}/${REGIONAL_OBF_FILE}"
fi
