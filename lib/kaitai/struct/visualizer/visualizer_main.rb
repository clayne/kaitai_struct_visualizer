require 'kaitai/struct/visualizer/version'
require 'kaitai/struct/visualizer/visualizer'
require 'kaitai/tui'

require 'open3'
require 'json'

module Kaitai::Struct::Visualizer

class ExternalCompilerVisualizer < Visualizer
  def compile_formats(fns)
    errs = false
    main_class_name = nil
    Dir.mktmpdir { |code_dir|
      args = ['--ksc-json-output', '--debug', '-t', 'ruby', *fns, '-d', code_dir]

      # UNIX-based systems run ksc via a shell wrapper that requires
      # extra '--' in invocation to disambiguate our '-d' from java runner
      # '-d' (which allows to pass defines to JVM). Windows-based systems
      # do not need and do not support this extra '--', so we don't add it
      # on Windows.
      args.unshift('--') unless Kaitai::TUI::is_windows?

      status = nil
      log_str = nil
      Open3.popen3('kaitai-struct-compiler', *args) { |stdin, stdout, stderr, wait_thr|
        status = wait_thr.value
        log_str = stdout.read
        err_str = stderr.read
      }

      if status != 0
        if status == 127
          $stderr.puts "ksv: unable to find and execute kaitai-struct-compiler in your PATH"
        else
          $stderr.puts "ksc crashed (exit status = #{status}):\n"
          $stderr.puts "== STDOUT\n"
          $stderr.puts log_str
          $stderr.puts
          $stderr.puts "== STDERR\n"
          $stderr.puts err_str
          $stderr.puts
        end
        exit status
      end

      log = JSON.load(log_str)

      # FIXME: add log results check
      puts "Compilation OK"

      fns.each_with_index { |fn, idx|
        puts "... processing #{fn} #{idx}"

        log_fn = log[fn]
        if log_fn['errors']
          report_err(log_fn['errors'])
          errs = true
        else
          log_classes = log_fn['output']['ruby']
          log_classes.each_pair { |k, v|
            compiled_name = v['files'][0]['fileName']
            compiled_path = "#{code_dir}/#{compiled_name}"

            puts "...... loading #{compiled_name}"
            require compiled_path
          }

          # Is it main ClassSpecs?
          if idx == 0
            main = log_classes[log_fn['firstSpecName']]
            main_class_name = main['topLevelName']
          end
        end
      }

    }

    if errs
      puts "Fatal errors encountered, cannot continue"
      exit 1
    else
      puts "Classes loaded OK, main class = #{main_class_name}"
    end

    return main_class_name
  end

  def report_err(err)
    puts "Error: #{err.inspect}"
  end
end

end
