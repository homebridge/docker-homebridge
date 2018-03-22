#!/usr/bin/env bats

teardown() {
  docker rm -f homebridge
}

launch() {
  docker run --name homebridge -d -p 51826:51826 -e TERMINATE_ON_ERROR=1 homebridge
  sleep 15
}

testCmd() {
  curl -I http://localhost:51826/accessories \
    && docker exec homebridge pidof homebridge
}

@test "test homebridge starts" {
  launch
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test homebridge starts after a graceful restart" {
  launch
  docker restart homebridge
  sleep 15
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test homebridge starts after being killed" {
  launch
  docker kill homebridge
  docker start homebridge
  sleep 15
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test container exits when homebridge process stops" {
  launch
  docker exec homebridge pkill homebridge
  sleep 10
  run docker exec homebridge echo "This should fail."
  [ "$status" -ne 0 ]
}

@test "test extra packages are installed" {
  docker run --name homebridge -d -e "PACKAGES=bats" homebridge
  sleep 30
  run docker exec homebridge which bats
  [ "$status" -eq 0 ]
}

@test "test homebridge-config-ui-x is running if option is enabled" {
  docker run --name homebridge -d -p 51826:51826 -p 8581:8581 -e HOMEBRIDGE_CONFIG_UI=1 -e HOMEBRIDGE_CONFIG_UI_PORT=8581 homebridge
  sleep 15
  run testCmd \
    && curl -If http://localhost:8581/favicon.ico \
    && docker exec homebridge pidof homebridge-config-ui-x
  [ "$status" -eq 0 ]
}

@test "test homebridge-config-ui-x not running if option is not enabled" {
  launch
  run docker exec homebridge pidof homebridge-config-ui-x
  [ "$status" -ne 0 ]
}
