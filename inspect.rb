
def get_conds
  names = Dir.glob( "asm/*.s" ).map{ |e| 
    m=%r!asm/(.*)_(\w)(\d+)\.s$!.match(e)
    m.to_a.drop(1)
  }
  targets, t, s = Array.new(3){ |ix|
    names.map{ |e| e[ix] }.uniq.sort
  }
  [ targets, t, s.map(&:to_i).sort ]
end

targets, types, counts = get_conds


def using_stack_x86(asm)
  s=/^_foo_\w+\:([\s\S]+?)(?:jmp|call)\s+_foo_\w+/.match(asm)[1]
  return false unless /^\s*mov\w*\s+\%\w+\s*\,\s*(\d+)\(\%esp\)/===s
  4<$1.to_i
end

def using_stack_x64(asm)
  s=/^_foo_\w+\:([\s\S]+?)(?:jmp|call)\s+_foo_\w+/.match(asm)[1]
  /^\s*mov\w*\s+\%\w+\s*\,\s*\d+\(\%rsp\)/===s
end

def using_stack_arm32(asm)
  /^\s*ldr\s+\w+\s*\,\s*\[\s*sp\s*\,/===asm ||
  /^\s*ldrd\s+\w+\s*\,\s*\[\s*sp\s*\,/===asm ||
  /^\s*vldr(?:\.\d+)?\s*\w+\s*\,\s*\[\s*sp\,/===asm ||
  /^\s*ldrd\s+\w+\s*\,\s*\[\s*sp/===asm
end

def using_stack_arm64(asm)
  s=/^foo_\w+\:([\s\S]+?)^\s*(?:bl|b)\s+foo_\w\s*$/.match(asm)[1]
  /\s*ldr\w*\s+/===s
end

def using_stack?(target,asm)
  case target
  when /^x86/
    using_stack_x86(asm)
  when /^x64/
    using_stack_x64(asm)
  when "cortex-a53-32hard", "cortex-a53-32soft", "cortex-m4-hard", "cortex-m4-soft"
    using_stack_arm32(asm)
  when "cortex-a53-ilp32", "cortex-a53-lp64"
    using_stack_arm64(asm)
  end
end


res=Hash.new{ |h,k| h[k]={} }
targets.each do |target|
  types.each do |vt|
    stack_limit = counts.find do |c|
      asm = File.open( "asm/#{target}_#{vt}#{c}.s", &:read )
      using_stack?(target,asm)
    end
    res[target][vt]=stack_limit
  end
end

def cat(t)
  case t
  when /^x86/
    "x86(32bit)"
  when /^x64/
    "amd64(64bit)"
  when "cortex-a53-32hard", "cortex-a53-32soft"
    "ARM(32bit)"
  when "cortex-m4-hard", "cortex-m4-soft"
    "ARM(32bit, Thumb)"
  when "cortex-a53-ilp32", "cortex-a53-lp64"
    "ARM(64bit)"
  end
end


puts( "|命令セット|条件|`uint8_t`|`int`|`void*`|`float`|`double`|")
puts( "|:--|:--|--:|--:|--:|--:|--:|")
res.each do |t,m|
  h=["",cat(t),t] + %w(b i p f d).map{ |t| m[t] }+[""]
  puts( h.join("|") )
end
