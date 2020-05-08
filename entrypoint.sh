#!/bin/sh -l

echo "Hello $1"
time=$(date)
echo "::set-output name=time::$time"

perldoc -l YAML::PP || true
perldoc -l YAML::PP::LibYAML || true
perldoc -l YAML::Tiny || true
perldoc -l YAML || true
perldoc -l XXX || true
