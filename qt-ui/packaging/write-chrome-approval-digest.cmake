cmake_minimum_required(VERSION 3.21)

file(SHA256 "${INPUT}" digest)
file(CONFIGURE OUTPUT "${OUTPUT}" CONTENT [=[
#pragma once
#define AURALIS_CHROME_APPROVAL_SHA256 "@digest@"
]=] @ONLY)
