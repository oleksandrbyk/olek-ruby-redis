TEST_FILES   := $(shell find test -name *_test.rb -type f)
REDIS_BRANCH := unstable
TMP          := tmp
BUILD_DIR    := ${TMP}/cache/redis-${REDIS_BRANCH}
TARBALL      := ${TMP}/redis-${REDIS_BRANCH}.tar.gz
BINARY       := ${BUILD_DIR}/src/redis-server
PID_PATH     := ${BUILD_DIR}/redis.pid
SOCKET_PATH  := ${BUILD_DIR}/redis.sock
PORT         := 6381

test: ${TEST_FILES}
	make start
	env SOCKET_PATH=${SOCKET_PATH} \
		ruby -v $$(echo $? | tr ' ' '\n' | awk '{ print "-r./" $$0 }') -e ''
	make stop

${TMP}:
	mkdir $@

${BINARY}: ${TMP}
	bin/build ${REDIS_BRANCH} ${TMP}

stop:
	(test -f ${PID_PATH} && (kill $$(cat ${PID_PATH}) || true) && rm -f ${PID_PATH}) || true

start: ${BINARY}
	echo ${BINARY}
	${BINARY}                     \
		--daemonize  yes            \
		--pidfile    ${PID_PATH}    \
		--port       ${PORT}        \
		--unixsocket ${SOCKET_PATH}

clean:
	(test -d ${BUILD_DIR} && cd ${BUILD_DIR}/src && make clean distclean) || true

.PHONY: test start stop
