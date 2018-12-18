#!/bin/bash -e
set -o pipefail

cd $GOPATH/src/github.com/hyperledger/fabric-test

echo "Update fabric-test submodules and install nodejs"

for TARGET in git-init git-latest fabric ca clean pre-setup; do
  make $TARGET
    if [ $? != 0 ]; then
      echo "FAILED: make $TARGET failed to execute"
      exit 1
    else
      echo "make $TARGET is successful"
      echo
    fi
done

###################
# Install govender
###################
echo "Install govendor"
go get -u github.com/kardianos/govendor

echo "======== PULL DOCKER IMAGES ========"

##########################################################
# Pull and Tag the fabric and fabric-ca images from Nexus
##########################################################
echo "Fetching images from Nexus"
NEXUS_URL=nexus3.hyperledger.org:10001
ORG_NAME="hyperledger/fabric"
ARCH=$(go env GOARCH)
: ${STABLE_VERSION:=1.3.1-stable}
STABLE_TAG=$ARCH-$STABLE_VERSION
echo "---------> STABLE_VERSION:" $STABLE_VERSION

cd $GOPATH/src/github.com/hyperledger/fabric

dockerTag() {
  for IMAGES in peer orderer ccenv tools ca ca-tools ca-peer ca-orderer ca-fvt; do
    echo "Images: $IMAGES"
    echo
    docker pull $NEXUS_URL/$ORG_NAME-$IMAGES:$STABLE_TAG
          if [ $? != 0 ]; then
             echo  "FAILED: Docker Pull Failed on $IMAGES"
             exit 1
          fi
    docker tag $NEXUS_URL/$ORG_NAME-$IMAGES:$STABLE_TAG $ORG_NAME-$IMAGES
    docker tag $NEXUS_URL/$ORG_NAME-$IMAGES:$STABLE_TAG $ORG_NAME-$IMAGES:$STABLE_TAG
    echo "$ORG_NAME-$IMAGES:$STABLE_TAG"
    echo "Deleting Nexus docker images: $IMAGES"
    docker rmi -f $NEXUS_URL/$ORG_NAME-$IMAGES:$STABLE_TAG
  done
}

dockerTag

echo
docker images | grep "hyperledger*"
echo

#####################################################
# Pull the fabric-chaincode-javaenv image from Nexus
#####################################################
if [ "$GERRIT_BRANCH" != "master" ]; then
       echo "========> SKIP: javaenv image is not available on $GERRIT_BRANCH"
else
       NEXUS_URL=nexus3.hyperledger.org:10001
       ORG_NAME="hyperledger/fabric"
       IMAGE=javaenv
       : ${JAVAENV:=amd64-1.3.0-stable}
       docker pull $NEXUS_URL/$ORG_NAME-$IMAGE:$JAVAENV
       docker tag $NEXUS_URL/$ORG_NAME-$IMAGE:$JAVAENV $ORG_NAME-$IMAGE
       docker tag $NEXUS_URL/$ORG_NAME-$IMAGE:$JAVAENV $ORG_NAME-$IMAGE:amd64-1.3.0
       docker tag $NEXUS_URL/$ORG_NAME-$IMAGE:$JAVAENV $ORG_NAME-$IMAGE:amd64-latest
       ######################################
       docker images | grep hyperledger/fabric-javaenv || true
fi
echo

# Set Nexus Snapshot URL
RELEASE_VERSION=${RELEASE_VERSION:=1.3.1-stable}
NEXUS_URL=https://nexus.hyperledger.org/content/repositories/snapshots/org/hyperledger/fabric/hyperledger-fabric-$RELEASE_VERSION/$ARCH.$RELEASE_VERSION-SNAPSHOT

# Download the maven-metadata.xml file
curl $NEXUS_URL/maven-metadata.xml > maven-metadata.xml
if grep -q "not found in local storage of repository" "maven-metadata.xml"; then
    echo  "FAILED: Unable to download from $NEXUS_URL"
else
    # Set latest tar file to the VERSION
    VERSION=$(grep value maven-metadata.xml | sort -u | cut -d "<" -f2|cut -d ">" -f2)
    echo "Version: $VERSION..."

    # Download tar.gz file and extract it
    mkdir -p $WD/bin
    cd $WD
    curl $NEXUS_URL/hyperledger-fabric-$RELEASE_VERSION-$VERSION.tar.gz | tar xz
    rm hyperledger-fabric-*.tar.gz
    cd -
    rm -f maven-metadata.xml
    echo "Finished pulling fabric..."
    export PATH=$WD/bin:$PATH
    echo "---"
