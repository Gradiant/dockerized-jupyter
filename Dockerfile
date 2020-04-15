FROM python:3.7-buster

LABEL maintainer="cgiraldo@gradiant.org" \
      organization="gradiant.org"

ENV JUPYTER_VERSION=6.0.3 \
    JUPYTER_PORT=8888 \
    JUPYTER_ENABLE_LAB=true \
    JUPYTERHUB_VERSION=1.1.0 

COPY packages /packages
##############################
# JUPYTER Python Base
##############################
RUN pip3 install -r /packages/base-requirements.txt && \
    jupyter serverextension enable --py nbgitpuller --sys-prefix && \
    # jupyterhub deps
    apt-get update && apt-get install -y npm nodejs && rm -rf /var/lib/apt/lists/* && \
    npm install -g configurable-http-proxy && \
    jupyter labextension install hub

##############################
# Python data science
##############################
RUN pip3 install -r /packages/science-requirements.txt

##############################
# Python Big Data
##############################
RUN apt-get update && apt-get install -y libsasl2-dev libsasl2-modules-gssapi-mit && rm -rf /var/lib/apt/lists/* && \
    pip3 install -r /packages/bigdata-requirements.txt && \
##  Adding hadoop 2.7.7 native libraries
    wget -qO- https://archive.apache.org/dist/hadoop/common/hadoop-2.7.7/hadoop-2.7.7.tar.gz | tar xvz -C /usr/local/lib hadoop-2.7.7/lib/native --strip-components=3

# Spark Support
## Installed openjdk-8 since spark 2.4.4 does not yet support Java 11

ENV JAVA_HOME=/usr/lib/jvm/default-jvm/ \
    SPARK_VERSION=2.4.5 \
    SPARK_HOME=/opt/spark
ENV PATH="$PATH:$SPARK_HOME/sbin:$SPARK_HOME/bin" \
    SPARK_URL="local[*]" \
    PYTHONPATH="${SPARK_HOME}/python/lib/pyspark.zip:${SPARK_HOME}/python/lib/py4j-src.zip:$PYTHONPATH" \
    SPARK_OPTS="" \
    PYSPARK_PYTHON=/usr/bin/python3

RUN apt-get update && \
    wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | apt-key add - && \
    echo "deb https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/ buster main" > /etc/apt/sources.list.d/80-adoptopenjdk.list && \
    apt-get update && apt-get install -y adoptopenjdk-8-hotspot && \
    rm /etc/apt/sources.list.d/80-adoptopenjdk.list && rm -rf /var/lib/apt/lists/* && \
    cd /usr/lib/jvm && ln -s adoptopenjdk-8-hotspot-amd64 default-jvm && \
    wget -qO- https://archive.apache.org/dist/spark/spark-$SPARK_VERSION/spark-$SPARK_VERSION-bin-hadoop2.7.tgz | tar xvz -C /opt && \
    ln -s /opt/spark-$SPARK_VERSION-bin-hadoop2.7 /opt/spark && \
    cd /opt/spark/python/lib && ln -s py4j-*-src.zip py4j-src.zip && \
    wget -qO $SPARK_HOME/jars/spark-avro_2.11-$SPARK_VERSION.jar \
      "https://repo1.maven.org/maven2/org/apache/spark/spark-avro_2.11/$SPARK_VERSION/spark-avro_2.11-$SPARK_VERSION.jar" &&\
    cp $SPARK_HOME/examples/jars/spark-examples_2.11-$SPARK_VERSION.jar $SPARK_HOME/jars

# https://spark.apache.org/docs/latest/sql-pyspark-pandas-with-arrow.html#compatibiliy-setting-for-pyarrow--0150-and-spark-23x-24x
#RUN cp /opt/spark/conf/spark-env.sh.template /opt/spark/conf/spark-env.sh && \
#    echo "ARROW_PRE_0_15_IPC_FORMAT=1" >> /opt/spark/conf/spark-env.sh
ENV ARROW_PRE_0_15_IPC_FORMAT=1

#####################################
# Scala kernel (Toree)
#####################################
RUN pip3 install toree==0.3.0 && \
    jupyter toree install --kernel_name="Spark - Local" --spark_home=${SPARK_HOME} && \
    jupyter toree install --kernel_name="Spark - Cluster" --spark_home=${SPARK_HOME} --spark_opts='--master=${SPARKCONF_SPARK_MASTER}'

#################################
# Java Libs
#################################
RUN wget https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.11/$SPARK_VERSION/spark-sql-kafka-0-10_2.11-$SPARK_VERSION.jar \
    -O /opt/spark/jars/spark-sql-kafka-0-10_2.11-$SPARK_VERSION.jar && \
    wget https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/2.0.0/kafka-clients-2.0.0.jar \
    -O /opt/spark/jars/kafka-clients-2.0.0.jar

##############################
# R layer (disabled)
##############################
# RUN apt-get update && apt-get install -y r-base r-base-dev libxml2-dev && rm -rf /var/lib/apt/lists/* && \
#    R -e "install.packages('IRkernel', repos = 'http://cran.us.r-project.org')" && \
#    R -e "IRkernel::installspec(user = FALSE)" && \
#    apt-get update && apt-get install -y libcurl4-openssl-dev libssl-dev && rm -rf /var/lib/apt/lists/* && \
#    R -e "install.packages(c('tidyverse'),repos = 'http://cran.us.r-project.org')" && \
#    R -e "install.packages('devtools', repos = 'http://cran.us.r-project.org')"

##############################
# Other tools layer (disabled)
##############################
#RUN pip3 install mlflow==1.3.0

# create a user, since we don't want to run as root
ENV NB_USER=jovyan
ENV NB_UID=1000
ENV NB_GID=100
ENV HOME=/home/jovyan

RUN apt-get update && apt-get install -y sudo tini && rm -rf /var/lib/apt/lists/* && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

WORKDIR $HOME
COPY files /

USER jovyan


