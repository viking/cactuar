guard :test do
  watch(%r{^lib/((?:[^/]+\/)*)(.+)\.rb$}) do |m|
    "test/unit/#{m[1]}test_#{m[2]}.rb"
  end
  watch(%r{^test/((?:[^/]+\/)*)test.+\.rb$})
  watch('test/helper.rb') { 'test' }
end
