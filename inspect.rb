
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
    m && [m[1],m[2][0],m[2].size]
  }.compact
  sorters = [
    ->(v){[is_name(v),v]},
    ->(v){"bsilpfdhgjkxy".index(v)},
    ->(v){v},
  ]
  Array.new(3){ |ix|
    names.map{ |e| e[ix] }.uniq.sort_by{ |v| sorters[ix][v] }
  }
end

def multi_conds
  names = Dir.glob( "asm/*.s" ).map{ |e|
    m=%r!asm/(.*)_(\w+)\.s$!.match(e)
    target = m[1]
    types = m[2]
    if types[0]!=types[-1]
      [target,types]
    else
      nil
    end
  }.compact
  Array.new(2){ |ix|
    names.map{ |e| e[ix] }.uniq.sort
  }
end

def dispname(e)
  {
    "b"=>"char",
    "s"=>"short",
    "i"=>"int32_t",
    "h"=>"char × 2",
    "g"=>"short × 1",
    "j"=>"int32_t × 2",
    "k"=>"int32_t × 4",
    "x"=>"int32_t + float",
    "y"=>"int32_t + double",
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
    # stm	ip, {r0, r1, r2, r3}
    ( line[0]=="stm" && line[2]=="{" && line.last=="}" && line[3..-2].all?{ |e| e.start_with?("r") } ) ||
    # strh	r2, [sp, #36]	@ movhi
    ( line[0]=="strh" && line[2]=="[" && line[3]=="sp" && line.last(3)==%w( ] @ movhi) )
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
      (line[0].start_with?("mov") && line[3,3]==%w[( %rsp )]) ||
      # pushq	%rsi
      (line[0]=="pushq" && line[1]&.start_with?("%r")) ||
      # pushq	$74
      (line[0]=="pushq" && line[1]&.start_with?("$")) ||
      # movq	%rax, 40(%rsp)
      (line[0].start_with?("mov") && line[1]&.start_with?("%r") && line[3,3]==%w[( %rsp )]) ||
      # movl	$0x42920000, 80(%rsp)
      (line[0].start_with?("mov") && line[1]&.start_with?("$") && line[3,3]==%w[( %rsp )]) ||
      # movq	$79, 128(%rsp)
      (line[0].start_with?("mov") && line[1]&.start_with?("$") && line[3,3]==%w[( %rsp )])
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

def single(targets, types, counts)
  puts <<~"HEAD"
    |命令セット|条件|#{types.map{ |e| "`#{dispname(e)}`" }.join("|")}|
    |:--|:--|#{types.map{ "--:" }.join("|")}|
  HEAD
  targets.each do |target|
    res = types.map{ |t| 
      counts.reverse.find{ |c|
        no_stack?(target, "asm/#{target}_#{t*c}.s")
      } || 0
    }
    puts( "|#{is_name(target)}|#{target}|#{res.join("|")}|" )
  end
end

def single_main
  targets, types, counts = single_conds
  etypes = "bsilfdp".chars
  puts( "\## 一種類の型\n\n")
  puts( "\n### 組み込み型\n\n")
  single( targets, types & etypes, counts )
  puts( "\n### 構造体\n\n")
  single( targets, types-etypes, counts )
end

def multi(target, t)
  tis = [0, -1].map{ |ix|
    [t[0][ix], t.map{ |e| e.count(e[ix]) }.max]
  }
  col_count = tis[1][1]
  tlist = tis.map{|tt,|dispname(tt)}.join("＼")
  puts <<~"HEAD"

    #### #{target}

    |#{tlist}|#{[*1..col_count].join("|")}|
    |:--|#{([":-:"]*col_count).join("|")}|
  HEAD
  prev_all_false=false
  (1..tis[0][1]).each do |l0|
    line = (1..tis[1][1]).map{ |l1|
      txt = tis[0][0]*l0 + tis[1][0]*l1
      no_stack?(target, "asm/#{target}_#{txt}.s")
    }
    break if prev_all_false && line.none?
    prev_all_false = line.none?
    cols=line.map{ |e| e ? "✅" : "❌" }.join("|")
    puts("|#{l0}|#{cols}|")
  end
end

def multi_main
  puts( "\n## 複数の型の混在\n\n")
  targets, types = multi_conds
  t0s = types.map{ |e| e.chars.uniq.sort.join }.sort.uniq
  t0s.each do |t0|
    t = types.select{ |e| (e.chars.uniq - t0.chars).empty? }.sort
    tlist = [t[0][0], t[-1][-1]].map{|e| dispname(e)}.join("＼")
    puts( "\n### #{tlist}\n\n")
    targets.each do |target|
      multi(target,t)
    end
  end
end

single_main
multi_main
