# Tyto API

API to manage courses, events, locations, and attendance tracking.

## Routes

All routes return JSON.

- GET  `/`: Root route shows if Web API is running
- GET  `api/v1/accounts/[username]`: Get a single account
- POST `api/v1/accounts`: Create a new account
- GET  `api/v1/courses`: Get list of all courses
- POST `api/v1/courses`: Create a new course
- GET  `api/v1/courses/[course_id]`: Get a single course
- GET  `api/v1/courses/[course_id]/events`: Get list of events for a course
- POST `api/v1/courses/[course_id]/events`: Create a new event for a course
- GET  `api/v1/courses/[course_id]/events/[event_id]`: Get a single event
- GET  `api/v1/courses/[course_id]/locations`: Get list of locations for a course
- POST `api/v1/courses/[course_id]/locations`: Create a new location for a course
- GET  `api/v1/courses/[course_id]/locations/[location_id]`: Get a single location

## Install

Install this API by cloning the *relevant branch* and use bundler to install
specified gems from `Gemfile.lock`:

```shell
bundle install
```

Copy `config/secrets-example.yml` to `config/secrets.yml` and adjust as needed.

Setup development database once:

```shell
rake db:migrate
```

Optionally populate the development database with sample accounts, courses,
enrollments, locations, and events:

```shell
rake db:seed
# or, to wipe and reseed from scratch:
rake reseed
```

## Execute

Run this API using:

```shell
puma
```

## Test

Setup test database once:

```shell
RACK_ENV=test rake db:migrate
```

Run the test specification:

```shell
rake spec
```

## Release check

Before submitting pull requests, please check if specs, style, and dependency
audits pass:

```shell
rake release_check
```

## For Contributors

- **Database schema** — see [`docs/schema.md`](docs/schema.md) for the
  entity-relationship diagram and the rationale behind encrypted columns,
  keyed-hash lookup, role enumeration, and cascade behavior.
