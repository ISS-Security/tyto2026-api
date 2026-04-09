# frozen_string_literal: true

# Loaded automatically by `rake console` (pry).
# Auto-formats Sequel model arrays as readable tables via table_print.
# Dev-only convenience; has no effect on the app or tests.

require 'table_print'

# Per-model default columns, so `tp Tyto::Course.all` and bare
# `Tyto::Course.all` both show sensible, non-overflowing output.
if defined?(Tyto::Course)
  tp.set Tyto::Course,   :id, :name, :description
  tp.set Tyto::Event,    :id, :course_id, :location_id, :name, :start_at, :end_at
  tp.set Tyto::Location, :id, :course_id, :name, :longitude, :latitude
end

# Make `Tyto::Course.all` (and other model arrays) auto-render as tables
# in pry, the way Hirb used to. Falls back to the default printer for
# everything else.
#
# NOTE: TablePrint::Printer.table_print returns a STRING and does not
# write to stdout itself — only the top-level `tp` helper puts it.
# Inside a Pry.config.print hook we have to write to `output` ourselves.
old_print = Pry.config.print
Pry.config.print = proc do |output, value, *rest|
  if value.is_a?(Array) && value.first.is_a?(Sequel::Model)
    output.puts TablePrint::Printer.table_print(value)
  else
    old_print.call(output, value, *rest)
  end
end

puts 'table_print enabled - Sequel model arrays auto-render as tables.'
