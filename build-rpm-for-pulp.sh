#!/bin/bash

set -x

SETUPTREE='rpmbuild'
RPMDIR='rpmdir'
REPO_NAME='qa'
REPO_BASE_DIR='/srv/repo/yum'
SPEC_REPO='git@github.com:ITV/spec.git'
# ARTIFACTORY_LOCATION='gilder-ci.itvplc.ads'
JENKINS_USER="jenkins"

#parameters passed by other jenkins jobs
ARTIFACTORY_LOCATION=${ARTIFACTORY_LOCATION}
PACKAGE_GROUP=${PACKAGE_GROUP}
PACKAGE_NAME=${PACKAGE_NAME}
PACKAGE_VERSION=${PACKAGE_VERSION}
PACKAGE_VERSION_SUFFIX=${PACKAGE_VERSION_SUFFIX}
RELEASE_NUMBER=${RELEASE_NUMBER}
PACKAGE_NAME_SUFFIX=${PACKAGE_NAME_SUFFIX}
PACKAGE_NAME_EXTENSION=${PACKAGE_NAME_EXTENSION}
QA_REPO=${QA_REPO}
BINARY="$PACKAGE_NAME$PACKAGE_NAME_SUFFIX-$PACKAGE_VERSION-$RELEASE_NUMBER$PACKAGE_VERSION_SUFFIX.$PACKAGE_NAME_EXTENSION"
PROJECT=${PROJECT}
TEAMNAME=${TEAMNAME}

function returnCode {

    return_code=$?
    if [ $return_code -ne 0 ];
    then
        exit 1
    fi

}

function binary {

    # copy sources to SOURCES
    rm -rf binary 2>/dev/null
    mkdir -p binary/rpm/centos/6/$PACKAGE_NAME
    if [ "$PROJECT" = 'cdm' ];
    then
        curl -fs http://$ARTIFACTORY_LOCATION/artifactory/libs-release-local/$PACKAGE_GROUP/$PACKAGE_NAME$PACKAGE_NAME_SUFFIX/$PACKAGE_VERSION-$RELEASE_NUMBER/$BINARY -o $SETUPTREE/SOURCES/$PACKAGE_NAME.$PACKAGE_NAME_EXTENSION
    else
        curl -fs http://$ARTIFACTORY_LOCATION/artifactory/simple/ext-release-local/$PACKAGE_GROUP/$PACKAGE_NAME$PACKAGE_NAME_SUFFIX/$PACKAGE_VERSION-$RELEASE_NUMBER/$BINARY -o $SETUPTREE/SOURCES/$PACKAGE_NAME.$PACKAGE_NAME_EXTENSION
    fi
    returnCode

}

function spec {

    #copy spec file to SPECS + things like init scripts to SOURCES
    rm -rf spec 2>/dev/null
    git clone $SPEC_REPO spec
    cp -v spec/rpm/centos/6/$PACKAGE_NAME/*.spec $SETUPTREE/SPECS/
    find spec/rpm/centos/6/$PACKAGE_NAME/ -type f -not -name '*.spec' -exec cp -v '{}' $SETUPTREE/SOURCES/ \;

    # modify spec version according to what the upstream job says it wants built
    sed -i "s/^Version.*/Version:        $PACKAGE_VERSION/" $SETUPTREE/SPECS/$PACKAGE_NAME.spec
    sed -i "s/^Release.*/Release:        $RELEASE_NUMBER/" $SETUPTREE/SPECS/$PACKAGE_NAME.spec

}

function buildSrpm {

    cleanRpmbuildDir
    mkdir -p $SETUPTREE/{BUILD,SRPMS,SPECS,SOURCES,RPMS}

    spec
    binary

    #find binary/rpm/centos/6/$PACKAGE_NAME/ -type f -not -name '*.spec' -exec cp -v '{}' $SETUPTREE/SOURCES/ \;
    # set the setuptree location http://stackoverflow.com/questions/416983/why-is-topdir-set-to-its-default-value-when-rpmbuild-called-from-tcl
    rpmbuild --define "_topdir $SETUPTREE" -bs $SETUPTREE/SPECS/$PACKAGE_NAME.spec
    returnCode

}

function cleanRpmbuildDir {

    printf "\nCleaning rpmbuild dir\n\n"
    rm -rfv $SETUPTREE
    returnCode
}

function build_rpm {

    echo "Cleaning $RPMDIR"
    rm -rf ./$RPMDIR/*
    #sudo /usr/sbin/mock --init -r centos-6-x86_64
    if [ -z "$TEAMNAME" ]
    then
        sudo /usr/sbin/mock -r centos-6-x86_64 --rebuild rpmbuild/SRPMS/*.src.rpm --resultdir=./$RPMDIR
    else
        sudo /usr/sbin/mock -r centos-6-x86_64 --rebuild rpmbuild/SRPMS/*.src.rpm --resultdir=./$RPMDIR --uniqueext=$TEAMNAME
    fi
    returnCode

}

printf " \n\n Cleaning old rpm setup tree \n\n "
# what happens if it is more than one package to be built ? - array of packages to be built ?
# there will only be one package to be built at one time, notified by upstream job that builds jar, or triggered manually
printf " \n\n Building srpm from spec + sources \n\n "
buildSrpm
printf " \n\n Building rpm from spec + sources using mock \n\n "
build_rpm

pulp-admin login -u admin -p admin
pulp-admin rpm repo uploads rpm --repo-id $QA_REPO -f ./rpmdir/$PACKAGE_NAME-$PACKAGE_VERSION-$RELEASE_NUMBER.noarch.rpm
pulp-admin rpm repo publish run  --repo-id $QA_REPO
