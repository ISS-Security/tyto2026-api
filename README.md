# Tyto API

API to manage courses, events, locations, and attendance tracking.

## Vulnerabilities

This branch (2-demo-db-vulnerabilities) allows mass assignment and SQL injection. It does not prevent the above attacks and loosens some of Roda's built-in precautions for demonstration purposes.

### Mass assignment

Conduct mass assignment via POST request:

```ruby
$ rake console
# type these within console:
req_header = { 'CONTENT_TYPE' => 'application/json' }
req_body = { name: 'Bad Date', created_at: '1900-01-01' }.to_json
post '/api/v1/courses', req_body, req_header
```

Conduct mass assignment in code:

```ruby
Tyto::Course.create(
  name: 'Future Course',
  description: 'Manipulated timestamps',
  created_at: Time.new(1900, 01, 01)
)
```

### SQL Injection

Conduct SQL injection via GET request vector:

```bash
http GET http://localhost:9292/api/v1/courses/2%20or%20id%3D1
```

Intent of attack is to cause code using naked SQL code to execute a manipulated SQL query as follows:

```ruby
app.DB['SELECT * FROM courses WHERE id=2 or id=1'].all.to_json
```

## Routes

All routes return JSON.

- GET  `/`: Root route shows if Web API is running
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
