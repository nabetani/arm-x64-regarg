require "fileutils"

SRC_FN = "hoge.c"

def dest_fn(cpu, name)
  "asm/#{cpu}_#{name}.s"
end

FileUtils.mkdir_p("asm")

Args = Struct.new( :arg_list ) do
  def name
    arg_list
  end
  def typename(e)
    {
      "b"=>"char",
      "s"=>"short",
      "i"=>"int",
      "l"=>"long long",
      "f"=>"float",
      "d"=>"double",
      "p"=>"void *"
    }[e] || (raise "unexpected type #{e}")
  end
  def decls
    arg_list.chars.map.with_index(0){ |e,ix| "#{typename(e)} v#{ix}" }.join(", ")
  end
  def values
    arg_list.chars.map.with_index(0){ |e,ix| "(#{typename(e)})#{ix+63}" }.join(", ")
  end
end

[*1..33].each do |i|
  [
    Args.new( "b"*i ),
    Args.new( "i"*i ),
    Args.new( "l"*i ),
    Args.new( "f"*i ),
    Args.new( "d"*i ),
    Args.new( "p"*i ),
  ].each do |a|
    File.open( SRC_FN, "w" ) do |f|
      f.puts <<~SRC
      enum{ assert_int_is_4bytes = 1/((sizeof(int)==4)?1:0) };
      enum{ assert_long_long_is_8bytes = 1/((sizeof(long long)==8)?1:0) };
        void caller_function (){
          extern void callee_function( #{a.decls}  );
          callee_function( #{a.values} );
        }
      SRC
    end
    %x( aarch64-none-elf-gcc -O2 #{SRC_FN} -mabi=ilp32 -mcpu=cortex-a53 -march=armv8-a -S -o #{dest_fn("cortex-a53-ilp32", a.name)} )
    %x( aarch64-none-elf-gcc -O2 #{SRC_FN} -mabi=lp64 -mcpu=cortex-a53 -march=armv8-a -S -o #{dest_fn("cortex-a53-lp64", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mcpu=cortex-a53 -mfloat-abi=hard -S -o #{dest_fn("cortex-a53-32hard", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mcpu=cortex-a53 -mfloat-abi=soft -S -o #{dest_fn("cortex-a53-32soft", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mthumb -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16 -S -o #{dest_fn("cortex-m4-hard", a.name)} )
    %x( arm-none-eabi-gcc -O2 #{SRC_FN} -mthumb -mcpu=cortex-m4 -mfloat-abi=soft -mfpu=fpv4-sp-d16 -S -o #{dest_fn("cortex-m4-soft", a.name)} )
    %x( gcc-10 -mabi=ms -O2 #{SRC_FN} -S -o #{dest_fn("x64ms", a.name)} )
    %x( gcc-10 -mabi=sysv -O2 #{SRC_FN} -S -o #{dest_fn("x64sysv", a.name)} )
  end
end
