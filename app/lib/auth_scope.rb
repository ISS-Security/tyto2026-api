# frozen_string_literal: true

module Tyto
  # OAuth-style authorization scope carried inside an AuthToken.
  #
  # A scope is a space-separated list of `resource:permission` grants, e.g.
  # `"courses:read attendances:write"`. The wildcard resource `*` matches any
  # resource, and `write` implies `read`. Two named scopes ship today:
  #   FULL      = "*:write"  (a full session token — write implies read)
  #   READ_ONLY = "*:read"   (a reduced API key handed to a read-only deputy)
  #
  # Policies ask `can_read?`/`can_write?` for their resource string before
  # applying role/ownership logic, so a leaked READ_ONLY key can never mutate
  # data even if the underlying account holds write-capable roles.
  class AuthScope
    ALL = '*'
    READ = 'read'
    WRITE = 'write'
    FULL = '*:write'
    READ_ONLY = '*:read'

    SEPARATOR = ' '
    DIVIDER = ':'

    def initialize(scopes = FULL)
      @scopes_str = scopes
      @scopes = {}
      scopes.split(SEPARATOR).each { |scope| add_scope(scope) }
    end

    def can_read?(resource)
      readable?(ALL) || readable?(resource)
    end

    def can_write?(resource)
      writeable?(ALL) || writeable?(resource)
    end

    def to_s
      @scopes_str
    end

    private

    # `write` implies `read`: a write grant satisfies a read check too.
    def readable?(resource)
      writeable?(resource) || permission_granted?(resource, READ)
    end

    def writeable?(resource)
      permission_granted?(resource, WRITE)
    end

    def permission_granted?(resource, permission)
      @scopes[resource]&.include?(permission) || false
    end

    def add_scope(scope)
      resource, permission = scope.split(DIVIDER)
      @scopes[resource] ||= []
      @scopes[resource] << permission
    end
  end
end
