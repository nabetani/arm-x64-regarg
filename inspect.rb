
def is_name( fn )
  begin
    case fn
    when /ilp32/, /lp64/
      "ARM(64bit)"
    when /cortex\-a53\-32/
      "ARM(32bit)"
    when /cortex\-m4/
      "ARM(32bit, Thumb)"
    when /x64/
      "amd64"
    end
  rescue => e
    p [ fn ]
    raise e
  end
end

def single_conds
  names = Dir.glob( "asm/*.s" ).map{ |e|
    m=%r!asm/(.*)_((\w)\3*)\.s$!.match(e)
    [m[1],m[2][0],m[2].size]
  }
  sorters = [
    ->(v){[is_name(v),v]},
    ->(v){"bsilpfdjkxy".index(v)},
    ->(v){v},
  ]
  Array.new(3){ |ix|
    names.map{ |e| e[ix] }.uniq.sort_by{ |v| sorters[ix][v] }
  }
end

def dispname(e)
  {
    "b"=>"char",
    "s"=>"short",
    "i"=>"int32_t",
    "j"=>"struct(int32_t × 2)",
    "k"=>"struct(int32_t × 4)",
    "x"=>"struct(int32_t + float)",
    "y"=>"struct(int32_t + double)",
    "l"=>"int64_t",
    "f"=>"float",
    "d"=>"double",
    "p"=>"void*"
  }[e] || (raise "unexpected type #{e}")
end

def lines_arm(body)
  body.split( /[\r\n]+/ ).map{ |line|
    elements = line.scan( /(?:\#\d+)|\w+|\W/ ).to_a
    elements.select{ |c| !(/^\s+$/===c || ","==c) }
  }.select{ |e| !e.empty? }
end

def stack_arm64(src)
  body = /^caller_function:$([\s\S]*)(?:b|bl)?\s+callee_function/.match(src)[1]
  lines_arm(body).any?{ |line|
    #stp	x29, x30, [sp, 208]
    ( line[0]=="stp" && line[3]=="[" && line[4]=="sp" && line.last=="]" ) ||
    # str	x0, [sp, 176]
    ( line[0]=="str" && line[2]=="[" && line[3]=="sp" && line.last=="]" )
  }
end

def stack_arm32(src)
  body = /^caller_function:$([\s\S]*)(?:b|bl)?\s+callee_function/.match(src)[1]
  lines_arm(body).any?{ |line|
    #stp	x29, x30, [sp, 208]
    ( line[0]=="stp" && line[3]=="[" && line[4]=="sp" && line.last=="]" ) ||
    # str	x0, [sp, 176]
    ( line[0]=="str" && line[2]=="[" && line[3]=="sp" && line.last=="]" ) ||
    # str	r3, [sp]
    ( line[0]=="str" && line[2]=="[" && line[3]=="sp" && line.last=="]" ) ||
    # strd	r4, [sp, #112]
    ( line[0]=="strd" && line[2]=="[" && line[3]=="sp" && line.last=="]" ) ||
    # str	r3, [sp, #24]	@ float
    ( line[0]=="str" && line[2]=="[" && line[3]=="sp" && line.last(3)==%w( ] @ float) ) ||
    # strd	r3, r2, [sp]
    ( line[0]=="strd" && line[3]=="[" && line[4]=="sp" && line.last=="]" ) ||
    # stm	sp, {r0, r1, r2, r3}
    ( line[0,3]==%w(stm sp {) )
  }
end

def lines_x64(body)
  body.split( /[\r\n]+/ ).map{ |line|
    elements = line.scan( /(?:\$0x[0-9a-fA-F]+)|(?:\$\d+)|(?:\%\w+)|\w+|\W/ ).to_a
    elements.select{ |c| !(/^\s+$/===c || ","==c) }
  }.select{ |e| !e.empty? }
end

def stack_x64(src)
  body = /^_caller_function:$([\s\S]*)(?:call|jmp)\s+_callee_function/.match(src)[1]
  lines_x64(body).any?{ |line|
    cond = (
      # movl	$71, 64(%rsp)
      (line[0]=="movl" && line[3,3]==%w[( %rsp )]) ||
      # pushq	$74
      (line[0]=="pushq" && line[1]&.start_with?("$")) ||
      #	movabsq	$4634978072750194688, %r10
      (line[0]=="movabsq" && line[1]&.start_with?("$") && line[2]&.start_with?("%r")) ||
      # movq	%rax, 40(%rsp)
      (line[0]=="movq" && line[1]&.start_with?("%r") && line[3,3]==%w[( %rsp )]) ||
      # movl	$0x42920000, 80(%rsp)
      (line[0]=="movl" && line[1]&.start_with?("$") && line[3,3]==%w[( %rsp )]) ||
      # movq	$79, 128(%rsp)
      (line[0]=="movq" && line[1]&.start_with?("$") && line[3,3]==%w[( %rsp )])
    )
    cond
  }
end

def no_stack?( target, fn )
  src = File.open(fn, &:read)
  begin
    case target
    when /ilp32/, /lp64/
      !stack_arm64(src)
    when /cortex\-a53\-32/, /cortex\-m4/
      !stack_arm32(src)
    when /x64/
      !stack_x64(src)
    end
  rescue => e
    p [ fn ]
    raise e
  end
end

def single
  targets, types, counts = single_conds
  puts <<~"HEAD"
    |命令セット|条件|#{types.map{ |e| "`#{dispname(e)}`" }.join("|")}|
    |:--|:--|#{types.map{ "--:" }.join("|")}|
  HEAD
  targets.each do |target|
    res = types.map{ |t| 
      counts.reverse.find{ |c|
        no_stack?(target, "asm/#{target}_#{t*c}.s")
      } || :nil
    }
    puts( "|#{is_name(target)}|#{target}|#{res.join("|")}|" )
  end
end

def main
  single
end

main
