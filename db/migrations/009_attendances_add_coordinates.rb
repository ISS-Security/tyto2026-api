# frozen_string_literal: true

require 'sequel'

# Additive migration (post-`5-deployable`, per Decision #10): student check-in
# coordinates are PII, so they are stored encrypted at rest. Columns are
# nullable because staff-recorded attendances (and pre-existing rows) carry no
# submitted coordinates.
Sequel.migration do
  change do
    alter_table(:attendances) do
      add_column :longitude_secure, String, text: true
      add_column :latitude_secure, String, text: true
    end
  end
end
