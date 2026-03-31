# Tyto API

API to manage courses, events, locations, and attendance tracking

## Routes

All routes return Json

- GET `/`: Root route shows if Web API is running
- GET `api/v1/courses/`: returns all course IDs
- GET `api/v1/courses/[ID]`: returns details about a single course with given ID
- POST `api/v1/courses/`: creates a new course

## Install

Install this API by cloning the *relevant branch* and installing required gems from `Gemfile.lock`:

```shell
bundle install
```

## Test

Run the test script:

```shell
ruby spec/api_spec.rb
```

## Execute

Run this API using:

```shell
puma
```
