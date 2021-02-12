#!/bin/bash -ex

echo "build CSAR"
TEMPDIR=`mktemp -d`
ROOT=`pwd`
FILES=$(fgrep "Entry-" TOSCA-Metadata/TOSCA.meta |awk '{print $2}')
cd Definitions/OtherTemplates/fortiweb-cnf-0.5.0-1
tar cvzf ../fortiweb-cnf-0.5.0-1.tgz *
cd $ROOT
cp fortiweb-cnf.mf.meta fortiweb-cnf.mf
echo "" >> fortiweb-cnf.mf
echo "Artifacts:" >> fortiweb-cnf.mf
for file in $FILES
do
  SHA512=$(sha512sum $file|awk '{print $1}')
  echo "Source: $file" >>fortiweb-cnf.mf
  echo "Algorithm: SHA512" >>fortiweb-cnf.mf
  echo "Hash: $SHA512" >>fortiweb-cnf.mf
  echo "" >> fortiweb-cnf.mf
done
tar cvzf fortiweb-cnf.csar.tgz fortiweb-cnf.mf Definitions/ Files/ TOSCA-Metadata/
