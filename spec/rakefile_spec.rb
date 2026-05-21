# frozen_string_literal: true

require_relative 'spec_helper'

# Regression guard: the seed task and any other db:* task that depends on
# :load_models must autoload `policies` so services that delegate to policy
# objects (e.g. CreateCourseForOwner -> AccountPolicy) don't NameError.
# Smoke-test 2026-05-21 hit `uninitialized constant Tyto::AccountPolicy`
# when this list was missing 'policies'.
describe 'Rakefile autoload conventions' do
  let(:rakefile) { File.read(File.expand_path('../Rakefile', __dir__)) }

  # Tolerates both %w[...] and ['a', 'b', ...] / ["a", "b", ...] forms.
  def load_models_folders(rakefile_text)
    block = rakefile_text.match(/task :load_models do.*?end/m)[0]
    if (m = block.match(/require_app\(\s*%w\[([^\]]+)\]\s*\)/))
      m[1].split
    elsif (m = block.match(/require_app\(\s*\[([^\]]+)\]\s*\)/))
      m[1].scan(/['"]([^'"]+)['"]/).flatten
    else
      []
    end
  end

  it 'db:load_models autoloads the policies folder' do
    _(load_models_folders(rakefile)).must_include 'policies'
  end

  it 'db:load_models autoloads every app/<folder> services + policies depend on' do
    folders = load_models_folders(rakefile)
    %w[config models policies services].each do |folder|
      _(folders).must_include folder
    end
  end
end
