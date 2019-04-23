require 'rubyserial'
require 'thor'

DEFAULT_REPEATS = 3
DEFAULT_DISTANCE = 50

class Calibrator

  def refine(ports)
    found = ports.size
    result = nil
    case
      when found == 1
        ports.first
      when found == 0
        puts 'No ttyACM or ttyUSB devices found'
        exit 1
      else
        loop do
          puts 'Please refine:'
          ports.each_with_index {|port, idx| puts "#{idx}: #{port}"}
          result = ports[STDIN.gets.to_i]
          break if result
        end
        result
    end
  end

  def find_port
    ports = `ls /dev/tty*`.split("\n").select do |name|
      name =~ /\/dev\/tty[A|U].+/
    end
    refine(ports)
  end

  def initialize(port)
    port = port || find_port
    puts "Using port: #{port}"
    @serial = Serial.new(port)
    puts "Connected to: #{info}"
  end

  def cmd(value)
    @serial.write("#{value}\n")
    result = []
    @serial.gets("\n") do |line|
      break if line =~ /^ok .*/
      result << line
    end
    result.join("\n")
  end

  def info
    cmd('M115')
  end

  def home_run(axis)
    cmd("G28 #{axis}") if axis
  end

  def move(axis, mm)
    cmd("G91")
    cmd("G1 #{axis}#{mm}")
  end

  def set_steps_per_unit(axis, value)
    cmd("M92 #{axis}#{value}")
    cmd("M500")
  end

  def steps_per_unit
    m503 = cmd('M503')
    matcher = /M92 X(?<x>[\d|\.]+) Y(?<y>[\d|\.]+) Z(?<z>[\d|\.]+) E(?<e>[\d|\.]+)/.match(m503)
    {x: matcher[:x].to_f, y: matcher[:y].to_f, z: matcher[:z].to_f, e: matcher[:e].to_f}
  end

  def finish
    cmd("M18")
    @serial.close
  end

  def calibrate_run(axis, distance)
   current_spu = steps_per_unit[axis.downcase.to_sym]
   puts "Calibrating #{axis}"
   puts 'Prepare ruler, press ENTER when ready'
   STDIN.gets
   home_run(axis)
   puts 'Axis homed. Set ruler to 0'
   puts "I'm about to move axis #{axis} to #{distance}mm mark, press ENTER when ready"
   STDIN.gets
   move(axis,distance)
   puts 'Type measured distance, press ENTER when ready'
   real_distance = STDIN.gets
   new_spu = current_spu*distance/real_distance.to_f
   puts "Current SPU:#{current_spu}, new SPU:#{new_spu}"
   set_steps_per_unit(axis, new_spu)
  end

  def calibrate(axis, repeat, distance)
    (repeat || DEFAULT_REPEATS).times { calibrate_run(axis, distance) }
    finish
  end

  def read()
    puts "Steps per unit: X:#{steps_per_unit[:x]} Y:#{steps_per_unit[:y]} Z:#{steps_per_unit[:z]} E:#{steps_per_unit[:e]}"
    finish
  end

  def position(axis, distance)
    move(axis, distance)
    finish
  end

  def home(axis)
    home_run(axis)
    finish
  end

end

class CalibratorCLI < Thor

  class_option :port, :desc => 'TTY device for printer connection'

  desc "calibrate AXIS", "Calibrate AXIS"
  option :repeats, :default => DEFAULT_REPEATS, :desc => 'Number of times to repeat calibration'
  option :distance, :default => DEFAULT_DISTANCE, :desc => 'Distance in mm to move axis'
  def calibrate(axis)
    Calibrator.new(options[:port]).calibrate(axis.upcase, options[:repeats], options[:distance])
  end

  desc "read", "Print current steps per unit info"
  def read()
    Calibrator.new(options[:port]).read
  end

  desc "position AXIS DISTANCE", "Move AXIS for DISTANCE mm"
  def position(axis, distance)
    Calibrator.new(options[:port]).position(axis.upcase, distance)
  end

  desc "home AXIS", "Home AXIS"
  def home(axis)
    Calibrator.new(options[:port]).home(axis.upcase)
  end

end

CalibratorCLI.start(ARGV)

