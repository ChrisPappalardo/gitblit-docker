FROM openjdk:8-jre-slim

ENV GITBLIT_VERSION 1.9.0
ENV GITBLIT_DOWNLOAD_SHA 349302ded75edfed98f498576861210c0fe205a8721a254be65cdc3d8cdd76f1

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever packages get added
RUN groupadd -r -g 8117 gitblit && useradd -r -M -g gitblit -u 8117 -d /opt/gitblit gitblit


LABEL maintainer="James Moger <james.moger@gitblit.com>, Florian Zschocke <f.zschocke+gitblit@gmail.com>" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.version="${GITBLIT_VERSION}"


ENV GITBLIT_DOWNLOAD_URL https://github.com/gitblit/gitblit/releases/download/v${GITBLIT_VERSION}/gitblit-${GITBLIT_VERSION}.tar.gz

# Install fetch dependencies, and gsou to step down from root
RUN set -eux ; \
    apt-get update && apt-get install -y --no-install-recommends \
        wget \
        gosu \
        ; \
    rm -rf /var/lib/apt/lists/* ; \
# Download and install Gitblit
    wget --progress=bar:force:noscroll -O gitblit.tar.gz ${GITBLIT_DOWNLOAD_URL} ; \
    echo "${GITBLIT_DOWNLOAD_SHA} *gitblit.tar.gz" | sha256sum -c - ; \
    mkdir -p /opt/gitblit ; \
    tar xzf gitblit.tar.gz -C /opt/gitblit --strip-components 1 ; \
    rm -f gitblit.tar.gz ; \
# Remove unneeded scripts.
    rm -f /opt/gitblit/install-service-*.sh ; \
    rm -r /opt/gitblit/service-*.sh ;








ENV GITBLIT_VAR /var/opt/gitblit

# Move the data files to a separate directory and set some defaults
RUN set -eux ; \
    gbetc=$GITBLIT_VAR/etc ; \
    gbsrv=$GITBLIT_VAR/srv ; \
    mkdir -p -m 0750 $gbsrv ; \
    mv /opt/gitblit/data/git $gbsrv ; \
    ln -s $gbsrv/git /opt/gitblit/data/git ; \
    mv /opt/gitblit/data $gbetc ; \
    ln -s $gbetc /opt/gitblit/data ; \
    \
# Make sure that the most current default properties file is available
# unedited to Gitblit.
    mkdir -p /opt/gitblit/etc/ ; \
    mv $gbetc/defaults.properties /opt/gitblit/etc ; \
    printf "\
6 c\\\n\
\\\n\
\\\n\
""#\\\n\
""# DO NOT EDIT THIS FILE. IT CAN BE OVERWRITTEN BY UPDATES.\\\n\
""# FOR YOUR OWN CUSTOM SETTINGS USE THE FILE ${gbetc}/gitblit.properties\\\n\
""# THIS FILE IS ONLY FOR REFERENCE.\\\n\
""#\\\n\
\\\n\
\\\n\
\n\
/^# Base folder for repositories/,/^git.repositoriesFolder/d\n\
/^# The location to save the filestore blobs/,/^filestore.storageFolder/d\n\
/^# Specify the location of the Lucene Ticket index/,/^tickets.indexFolder/d\n\
/^# The destination folder for cached federation proposals/,/^federation.proposalsFolder/d\n\
/^# The temporary folder to decompress/,/^server.tempFolder/d\n\
s/^server.httpPort.*/#server.httpPort = 8080/\n\
s/^server.httpsPort.*/#server.httpsPort = 8443/\n\
s/^server.redirectToHttpsPort.*/#server.redirectToHttpsPort = true/\n\
    " > /tmp/defaults.sed ; \
    sed -f /tmp/defaults.sed /opt/gitblit/etc/defaults.properties > $gbetc/defaults.properties ; \
    rm -f /tmp/defaults.sed ; \
#   Check that removal worked
    grep  "^git.repositoriesFolder" $gbetc/defaults.properties && false ; \
    grep  "^filestore.storageFolder" $gbetc/defaults.properties && false ; \
    grep  "^tickets.indexFolder" $gbetc/defaults.properties && false ; \
    grep  "^federation.proposalsFolder" $gbetc/defaults.properties && false ; \
    grep  "^server.tempFolder" $gbetc/defaults.properties && false ; \
    \
# Create a system.properties file that sets the defaults for this docker setup.
# This is not available outside and should not be changed.
    echo "git.repositoriesFolder = ${gbsrv}/git" >  /opt/gitblit/etc/system.properties ; \
    echo "filestore.storageFolder = ${gbsrv}/lfs" >> /opt/gitblit/etc/system.properties ; \
    echo "tickets.indexFolder = ${gbsrv}/tickets/lucene" >> /opt/gitblit/etc/system.properties ; \
    echo "federation.proposalsFolder = ${gbsrv}/fedproposals" >> /opt/gitblit/etc/system.properties ; \
    echo "server.tempFolder = ${GITBLIT_VAR}/temp" >> /opt/gitblit/etc/system.properties ; \
    echo "server.httpPort = 8080" >> /opt/gitblit/etc/system.properties ; \
    echo "server.httpsPort = 8443" >> /opt/gitblit/etc/system.properties ; \
    echo "server.redirectToHttpsPort = true" >> /opt/gitblit/etc/system.properties ; \
    \
# Create a properties file for settings that can be set via environment variables from docker
    printf '\
''#\n\
''# GITBLIT-DOCKER.PROPERTIES\n\
''#\n\
''# This file is used by the docker image to store settings that are defined\n\
''# via environment variables. The settings in this file are automatically changed,\n\
''# added or deleted.\n\
''#\n\
''# Do not define your custom settings in this file. Your overrides or\n\
''# custom settings should be defined in the "gitblit.properties" file.\n\
''#\n\
include = /opt/gitblit/etc/defaults.properties,/opt/gitblit/etc/system.properties\
\n' > $gbetc/gitblit-docker.properties ; \
# Currently RPC is enabled by default
    echo "web.enableRpcManagement=true" >> $gbetc/gitblit-docker.properties ; \
    echo "web.enableRpcAdministration=true" >> $gbetc/gitblit-docker.properties ; \
    sed -i -e 's/^web.enableRpcManagement.*/#web.enableRpcManagement=true/' \
           -e 's/^web.enableRpcAdministration.*/#web.enableRpcAdministration=true/' \
        $gbetc/defaults.properties ; \
    \
# Create the gitblit.properties file that the user can use for customization.
    printf '\
''#\n\
''# GITBLIT.PROPERTIES\n\
''#\n\
''# Define your custom settings in this file and/or include settings defined in\n\
''# other properties files.\n\
''#\n\
\n\
''# NOTE: Gitblit will not automatically reload "included" properties.  Gitblit\n\
''# only watches the "gitblit.properties" file for modifications.\n\
''#\n\
''# Paths may be relative to the ${baseFolder} or they may be absolute.\n\
''#\n\
''# ONLY append your custom settings files at the END of the "include" line.\n\
''# The present files define the default settings for the docker container. If you\n\
''# remove them or change the order, things may break.\n\
''#\n\
include = gitblit-docker.properties\n\
\n\
''#\n\
''# Define your overrides or custom settings below\n\
''#\n\
\n' > $gbetc/gitblit.properties ; \
    \
    \
# Change ownership to gitblit user for all files that the process needs to write
    chown -R gitblit:gitblit $GITBLIT_VAR ; \
# Set file permissions so that gitblit can read all and others cannot mess up
# or read private data
    chmod -R o-rwx $gbsrv ; \
    chmod -R u+rwxs $gbsrv $gbsrv/git ; \
    chmod -R u+rwxs $gbetc ; \
    chmod -R o-rwx $gbetc ; \
    chmod ug=r $gbetc/defaults.properties ; \
    chmod g-w $gbetc/gitblit-docker.properties ; \
    chmod 0664 $gbetc/gitblit.properties ;



# Setup the Docker container environment
ENV PATH /opt/gitblit:$PATH

WORKDIR /opt/gitblit

VOLUME $GITBLIT_VAR


COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

# 8080:  HTTP front-end and transport
# 8443:  HTTPS front-end and transport
# 9418:  Git protocol transport
# 29418: SSH transport
EXPOSE 8080 8443 9418 29418
CMD ["gitblit"]
