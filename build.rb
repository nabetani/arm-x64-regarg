require "fileutils"

SRC_FN = "hoge.c"

def dest_fn(cpu, name)
  "asm/#{cpu}_#{name}.s"
end

FileUtils.mkdir_p("asm")

Args = Struct.new( :b, :i, :f, :d, :p ) do
  def name
    [
      (0<(b||0) ? "b#{b}" : nil ),
      (0<(i||0) ? "i#{i}" : nil ),
      (0<(f||0) ? "f#{f}" : nil ),
      (0<(d||0) ? "d#{d}" : nil ),
      (0<(p||0) ? "p#{p}" : nil ),
    ].compact.join("_")
  end
  def arg(n, v, t)
    Array.new(n||0){ |i| "#{t} #{v}#{i}" }
  end
  def args
    [
      arg(b, "b", "uint8_t"),
      arg(i, "i", "int"),
      arg(f, "f", "float"),
      arg(d, "d", "double"),
      arg(p, "p", "void *"),
    ].flatten.join(",")
  end
  def call_func(n, v)
    Array.new(n||0){ |i| "foo_#{v}(#{v}#{i});" }
  end
  def use
    [
      call_func(b, "b"),
      call_func(i, "i"),
      call_func(f, "f"),
      call_func(d, "d"),
      call_func(p, "p"),
    ].flatten.join("\n")
  end
end

[*1..33].each do |i|
  [
    Args.new( i, 0, 0, 0, 0 ),
    Args.new( 0, i, 0, 0, 0 ),
    Args.new( 0, 0, i, 0, 0 ),
    Args.new( 0, 0, 0, i, 0 ),
    Args.new( 0, 0, 0, 0, i ),
  ].each do |a|
    File.open( SRC_FN, "w" ) do |f|
      f.puts <<~SRC
        typedef unsigned char uint8_t;
        void foo_b(uint8_t);
        void foo_i(int);
        void foo_f(float);
        void foo_d(double);
        void foo_p(void *);
        void foo_#{a.name} ( #{a.args} ){
          #{a.use}
        }
      SRC
    end
    %x( aarch64-none-elf-gcc -O2 #{SRC_FN} -mabi=ilp32 -mcpu=cortex-a53 -march=armv8-a+fp+fp16 -S -o #{dest_fn("cortex-a53-ilp32", a.name)} )
    %x( aarch64-none-elf-gcc -O2 #{SRC_FN} -mabi=lp64 -mcpu=cortex-a53 -march=armv8-a+fp+fp16 -S -o #{dest_fn("cortex-a53-lp64", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mcpu=cortex-a53 -mfloat-abi=hard -S -o #{dest_fn("cortex-a53-32hard", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mcpu=cortex-a53 -mfloat-abi=soft -S -o #{dest_fn("cortex-a53-32soft", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mthumb -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16 -S -o #{dest_fn("cortex-m4-hard", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mthumb -mcpu=cortex-m4 -mfloat-abi=soft -mfpu=fpv4-sp-d16 -S -o #{dest_fn("cortex-m4-soft", a.name)} )
    %x( gcc-10 -mabi=ms -O2 #{SRC_FN} -S -o #{dest_fn("x64ms", a.name)} )
    %x( gcc-10 -mabi=sysv -O2 #{SRC_FN} -S -o #{dest_fn("x64sysv", a.name)} )
    %x( gcc-10 -mabi=ms -m32 -O2 #{SRC_FN} -S -o #{dest_fn("x86ms", a.name)} )
    %x( gcc-10 -mabi=sysv -m32 -O2 #{SRC_FN} -S -o #{dest_fn("x86sysv", a.name)} )
  end
end
