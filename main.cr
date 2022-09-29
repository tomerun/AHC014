START_TIME     = Time.utc.to_unix_ms
TL             = (ENV["TL"]? || 900).to_i
PART           = (ENV["PART"]? || 1).to_i
INITIAL_COOLER = (ENV["IC"]? || 3).to_f * 0.0001
FINAL_COOLER   = (ENV["FC"]? || 100).to_f * 0.0001
INF            = 1 << 28
EMPTY          = INF - 1
COUNTER        = Counter.new
STOPWATCH      = StopWatch.new
RND            = XorShift.new(2u64)
DR             = [-1, -1, 0, 1, 1, 1, 0, -1]
DC             = [0, -1, -1, -1, 0, 1, 1, 1]

class XorShift
  TO_DOUBLE = 0.5 / (1u64 << 63)
  @gauss : Float64

  def initialize(@x = 123456789u64)
    @gauss = INF.to_f64
  end

  def next_int
    @x ^= @x << 13
    @x ^= @x >> 17
    @x ^= @x << 5
    return @x
  end

  def next_int(m)
    return next_int % m
  end

  def next_double
    return TO_DOUBLE * next_int
  end
end

class StopWatch
  def initialize
    @start_at = Hash(String, Int64).new
    @sum = Hash(String, Int64).new(0i64)
  end

  def start(name)
    {% if flag?(:local) %}
      @start_at[name] = Time.utc.to_unix_ms
    {% end %}
  end

  def stop(name)
    {% if flag?(:local) %}
      @sum[name] += Time.utc.to_unix_ms - @start_at[name]
    {% end %}
  end

  def to_s(io)
    {% if flag?(:local) %}
      io << @sum
    {% end %}
  end
end

class Counter
  def initialize
    @hist = [] of Int32
  end

  def add(i)
    while @hist.size <= i
      @hist << 0
    end
    @hist[i] += 1
  end

  def to_s(io)
    io << "counter:\n"
    ((@hist.size + 9) // 10).times do |i|
      io << @hist[((i * 10)...(i * 10 + 10))]
      io << "\n"
    end
  end
end

macro debug(msg)
  {% if flag?(:local) %}
    STDERR.puts({{msg}})
  {% end %}
end

macro debugf(format_string, *args)
  {% if flag?(:local) %}
    STDERR.printf({{format_string}}, {{*args}})
  {% end %}
end

def crash(msg, caller_line = __LINE__)
  STDERR.puts "[ERROR] line #{caller_line}: #{msg}"
  exit
end

macro assert(cond, msg = "", caller_line = __LINE__)
  {% if flag?(:local) %}
    if !({{cond}})
      crash({{msg}}, {{caller_line}})
    end
  {% end %}
end

def shuffle(a)
  (a.size - 1).times do |i|
    pos = RND.next_int(a.size - i) + i
    a[i], a[pos] = a[pos], a[i]
  end
end

def dist2(y0, x0, y1, x1)
  return (y0 - y1) ** 2 + (x0 - x1) ** 2
end

#####################
# end of template/lib
#####################

struct Pos
  getter :y, :x

  def initialize(@y : Int32, @x : Int32)
  end
end

struct Rect
  include Enumerable(Pos)
  getter :p0, :size0, :size1, :dir

  def initialize(@p0 : Pos, @size0 : Int32, @size1 : Int32, @dir : Int32)
  end

  def as_coords
    dy = DR[@dir]
    dx = DC[@dir]
    ps = [p0.x, p0.y, p0.x + dx * @size0, p0.y + dy * @size0]
    dy, dx = dx * -1, dy
    ps << ps[-2] + dx * @size1
    ps << ps[-2] + dy * @size1
    dy, dx = dx * -1, dy
    ps << ps[-2] + dx * @size0
    ps << ps[-2] + dy * @size0
    return ps.join(" ")
  end

  def y
    @p0.y
  end

  def x
    @p0.x
  end

  def each
    dy = DR[@dir]
    dx = DC[@dir]
    y = p0.y + dy * @size0
    x = p0.x + dx * @size0
    yield Pos.new(y, x)
    dy, dx = dx * -1, dy
    y += dy * @size1
    x += dx * @size1
    yield Pos.new(y, x)
    dy, dx = dx * -1, dy
    y += dy * @size0
    x += dx * @size0
    yield Pos.new(y, x)
  end
end

class Result
  getter :rects, :score

  def initialize(@rects : Array(Rect), @score : Int32)
  end

  def to_s(io)
    io << @rects.size << "\n"
    io << @rects.map { |r| r.as_coords }.join("\n")
  end
end

RES_EMPTY = Result.new([] of Rect, 0)

def next_dir(d)
  return (d + 2) & 7
end

class Solver
  getter :n, :m, :s
  @n : Int32
  @m : Int32
  @has_point : Array(UInt64)

  def initialize
    @n, @m = read_line.split.map(&.to_i)
    @sxs = Array(Int32).new(@m, 0)
    @sys = Array(Int32).new(@m, 0)
    @ps = [] of Pos
    @base_score = 0
    @bbox_b = @n
    @bbox_t = 0
    @bbox_l = @n
    @bbox_r = 0
    @initial_has_point = [Array.new(@n, 0u64), Array.new(@n * 2 - 1, 0u64), Array.new(@n, 0u64), Array.new(@n * 2 - 1, 0u64)] of Array(UInt64)
    @has_point_bit = [Array.new(@n, 0u64), Array.new(@n * 2 - 1, 0u64), Array.new(@n, 0u64), Array.new(@n * 2 - 1, 0u64)] of Array(UInt64)
    @has_point = @has_point_bit[2]
    @m.times do |i|
      @sxs[i], @sys[i] = read_line.split.map(&.to_i)
      @base_score += w(@sys[i], @sxs[i])
      @bbox_b = {@bbox_b, @sys[i]}.min
      @bbox_t = {@bbox_t, @sys[i]}.max
      @bbox_l = {@bbox_l, @sxs[i]}.min
      @bbox_r = {@bbox_r, @sxs[i]}.max
      @initial_has_point[0][@sxs[i]] |= 1u64 << @sys[i]
      @initial_has_point[2][@sys[i]] |= 1u64 << @sxs[i]
      @initial_has_point[1][@n - 1 - (@sys[i] - @sxs[i])] |= 1u64 << @sys[i]
      @initial_has_point[3][@sys[i] + @sxs[i]] |= 1u64 << @sys[i]
    end
    @has_edge = Array(Array(Int32)).new(@n) { Array.new(@n, 0) }
    @s = 0
    @n.times do |i|
      @n.times do |j|
        @s += w(i, j)
      end
    end
    debug("n:#{@n} m:#{@m} s:#{@s}")
  end

  def w(p)
    return dist2(p.y, p.x, @n // 2, @n // 2) + 1
  end

  def w(y, x)
    return dist2(y, x, @n // 2, @n // 2) + 1
  end

  def inside(coord)
    return 0 <= coord && coord < @n
  end

  def verify(rects)
    exist_point = Array.new(@n) { Array.new(@n, false) }
    exist_edge = Array.new(@n) { Array.new(@n) { Array.new(8, false) } }
    @m.times do |i|
      exist_point[@sys[i]][@sxs[i]] = true
    end
    rects.size.times do |i|
      rect = rects[i]
      assert(!exist_point[rect.p0.y][rect.p0.x], [rects, i])
      exist_point[rect.p0.y][rect.p0.x] = true
      s0, s1 = rect.size0, rect.size1
      dir = rect.dir
      y = rect.p0.y
      x = rect.p0.x
      4.times do
        exist_edge[y][x][dir] = true
        exist_edge[y + DR[dir]][x + DC[dir]][dir ^ 4] = true
        (s0 - 1).times do
          y += DR[dir]
          x += DC[dir]
          assert(!exist_point[y][x], [rects, i, y, x])
          assert(!exist_edge[y][x][dir], [rects, i, y, x])
          exist_edge[y][x][dir] = true
          exist_edge[y + DR[dir]][x + DC[dir]][dir ^ 4] = true
        end
        y += DR[dir]
        x += DC[dir]
        assert(exist_point[y][x], [rects, i, y, x])
        s0, s1 = s1, s0
        dir = next_dir(dir)
      end
    end
  end

  def solve(timelimit)
    orig_ps = Array.new(@m) { |i| Pos.new(@sys[i], @sxs[i]) }
    @ps = orig_ps.dup
    best_res = solve_one(RES_EMPTY)
    cur_res = best_res
    turn = 0
    cooler = INITIAL_COOLER
    begin_time = Time.utc.to_unix_ms
    total_time = timelimit - begin_time
    last_update_turn = 0
    while true
      if (turn & 0xF) == 0
        cur_time = Time.utc.to_unix_ms
        if cur_time >= timelimit
          debug("total_turn: #{turn}")
          break
        end
        ratio = (cur_time - begin_time) / total_time
        cooler = Math.exp(Math.log(INITIAL_COOLER) * (1.0 - ratio) + Math.log(FINAL_COOLER) * ratio)
        if turn > last_update_turn + 5000
          cur_res = best_res
          last_update_turn = turn
          debug("revert turn:#{turn}")
        end
      end
      @ps = orig_ps.dup
      res = solve_one(cur_res)
      if accept(res.score - cur_res.score, cooler)
        COUNTER.add(0)
        if res.score > best_res.score
          COUNTER.add(1)
          debug("best_score:#{res.score} turn:#{turn}")
          best_res = res
          last_update_turn = turn
        end
        cur_res = res
      end
      turn += 1
    end
    verify(best_res.rects)
    return best_res
  end

  def accept(diff, cooler)
    return true if diff >= 0
    v = diff * cooler
    return false if v < -8
    return RND.next_double < Math.exp(v)
  end

  def solve_one(prev_result)
    STOPWATCH.start("init")
    4.times do |i|
      @has_point_bit[i][0, @has_point_bit[i].size] = @initial_has_point[i]
    end
    @has_edge.each { |row| row.fill(0) }
    score = @base_score
    STOPWATCH.stop("init")

    rects = [] of Rect
    if !prev_result.rects.empty?
      # 前回の結果からいくつかの四角とその依存先を削除する
      STOPWATCH.start("retain")
      if (RND.next_int & 0x1F) == 0
        rm_pos = prev_result.rects[RND.next_int(prev_result.rects.size)].p0
        rm_b = rm_pos.y - RND.next_int(5).to_i
        rm_t = rm_pos.y + RND.next_int(5).to_i
        rm_l = rm_pos.x - RND.next_int(5).to_i
        rm_r = rm_pos.x + RND.next_int(5).to_i
        prev_result.rects.each do |rect|
          if rm_b <= rect.y && rect.y <= rm_t && rm_l <= rect.x && rect.x <= rm_r
            next
          end
          if rect.any? { |p| @has_point[p.y].bit(p.x) == 0 }
            next
          end
          add(rect)
          rects << rect
          score += w(rect.p0)
        end
      else
        # 前回の結果からいくつかの四角とその依存元を保持する
        prob_retain = RND.next_int(3) + 1
        prev_result.rects.reverse_each do |rect|
          if @has_point[rect.y].bit(rect.x) != 0 || (RND.next_int & 15) <= prob_retain
            add(rect)
            rects << rect
            score += w(rect.p0)
            @has_point[rect.y] |= 1u64 << rect.x
            rect.each do |p|
              @has_point[p.y] |= 1u64 << p.x
            end
          end
        end
        rects.reverse!
      end
      STOPWATCH.stop("retain")
      # debug("retain:#{rects.size} out of #{prev_result.rects.size}")
    end
    shuffle(@ps)
    STOPWATCH.start("find")
    initial_si = @ps.size
    initial_si.times do |i|
      by = @ps[i].y
      bx = @ps[i].x
      dirs = ~(@has_edge[by][bx] | (@has_edge[by][bx] >> 2) | (@has_edge[by][bx] << 6)) & 0xFF
      while dirs != 0
        dir0 = dirs.trailing_zeros_count
        dirs &= dirs - 1
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        rect = find_rect_cw(by, bx, s0, dir0)
        next if !rect
        add(rect)
        rects << rect
        score += w(rect.p0)
        dirs &= ~@has_edge[by][bx]
      end
    end
    pi = initial_si
    while pi < @ps.size
      by = @ps[pi].y
      bx = @ps[pi].x
      dirs = ~(@has_edge[by][bx] | (@has_edge[by][bx] >> 2) | (@has_edge[by][bx] << 6)) & 0xFF
      while dirs != 0
        dir0 = dirs.trailing_zeros_count
        dirs &= dirs - 1
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        rect = find_rect_cw(by, bx, s0, dir0)
        if !rect
          rect = find_rect_both(by, bx, s0, dir0)
        end
        if rect
          add(rect)
          rects << rect
          score += w(rect.p0)
          dirs &= ~@has_edge[by][bx]
        end
      end
      dirs = ~(@has_edge[by][bx] | (@has_edge[by][bx] >> 6) | (@has_edge[by][bx] << 2)) & 0xFF
      while dirs != 0
        dir0 = dirs.trailing_zeros_count
        dirs &= dirs - 1
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        rect = find_rect_ccw(by, bx, s0, dir0)
        if rect
          add(rect)
          rects << rect
          score += w(rect.p0)
          dirs &= ~@has_edge[by][bx]
        end
      end
      pi += 1
    end
    STOPWATCH.stop("find")
    return Result.new(rects, score)
  end

  # def find_rect(by, bx, initial)
  #   dirs = @has_edge[by][bx] ^ 0xFF
  #   if !initial
  #     while dirs != 0
  #       dir0 = dirs.trailing_zeros_count
  #       dirs &= dirs - 1
  #       s0 = dist_nearest(by, bx, dir0)
  #       next if s0 == -1
  #       rect = find_rect_cw(by, bx, s0, dir0)
  #       if rect
  #         return rect
  #       end

  #       rect = find_rect_ccw(by, bx, s0, dir0)
  #       if rect
  #         return rect
  #       end

  #       rect = find_rect_both(by, bx, s0, dir0)
  #       if rect
  #         return rect
  #       end
  #     end
  #   else
  #     while dirs != 0
  #       dir0 = dirs.trailing_zeros_count
  #       dirs &= dirs - 1
  #       s0 = dist_nearest(by, bx, dir0)
  #       next if s0 == -1
  #       rect = find_rect_cw(by, bx, s0, dir0)
  #       if rect
  #         return rect
  #       end
  #     end
  #   end
  #   return nil
  # end

  def find_rect_cw(by, bx, s0, dir0)
    dir1 = next_dir(dir0)
    return nil if @has_edge[by][bx].bit(dir1) != 0
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    return nil if @has_edge[cy0][cx0].bit(dir1) != 0
    s1 = dist_nearest(cy0, cx0, dir1)
    return nil if s1 == -1
    s11 = dist_nearest(by, bx, dir1)
    return nil if (0 < s11) && (s11 <= s1)
    cy2 = by + DR[dir1] * s1
    cx2 = bx + DC[dir1] * s1
    assert(cy0 + DR[dir1] * s1 == cy2 + DR[dir0] * s0)
    assert(cx0 + DC[dir1] * s1 == cx2 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_edge[cy2][cx2].bit(dir0) != 0
    return nil if dist_nearest(cy2, cx2, dir0) != s0
    return Rect.new(Pos.new(cy2, cx2), s1, s0, dir1 ^ 4)
  end

  def find_rect_ccw(by, bx, s0, dir0)
    dir1 = next_dir(dir0) ^ 4
    return nil if @has_edge[by][bx].bit(dir1) != 0
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    return nil if @has_edge[cy0][cx0].bit(dir1) != 0
    s1 = dist_nearest(cy0, cx0, dir1)
    return nil if s1 == -1
    s11 = dist_nearest(by, bx, dir1)
    return nil if (0 < s11) && (s11 <= s1)
    cy2 = by + DR[dir1] * s1
    cx2 = bx + DC[dir1] * s1
    assert(cy0 + DR[dir1] * s1 == cy2 + DR[dir0] * s0)
    assert(cx0 + DC[dir1] * s1 == cx2 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_edge[cy2][cx2].bit(dir0) != 0
    return nil if dist_nearest(cy2, cx2, dir0) != s0
    return Rect.new(Pos.new(cy2, cx2), s0, s1, dir0)
  end

  def find_rect_both(by, bx, s0, dir0)
    dir1 = next_dir(dir0)
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    return nil if @has_edge[cy0][cx0].bit(dir1) != 0
    return nil if @has_edge[by][bx].bit(dir1) != 0
    s1 = dist_nearest(by, bx, dir1)
    return nil if s1 == -1
    s11 = dist_nearest(cy0, cx0, dir1)
    return nil if (0 < s11) && (s11 <= s1)
    cy1 = by + DR[dir1] * s1
    cx1 = bx + DC[dir1] * s1
    cy2 = cy0 + DR[dir1] * s1
    cx2 = cx0 + DC[dir1] * s1
    assert(cy2 == cy1 + DR[dir0] * s0)
    assert(cx2 == cx1 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_edge[cy1][cx1].bit(dir0) != 0
    return nil if dist_nearest(cy2, cx2, dir0 ^ 4) != s0
    return Rect.new(Pos.new(cy2, cx2), s0, s1, dir0 ^ 4)
  end

  def dist_nearest(y, x, dir)
    case dir
    when 0
      v = @has_point_bit[0][x] & ((1u64 << y) - 1)
      return v == 0 ? -1 : y - (63 - v.leading_zeros_count.to_i)
    when 1
      v = @has_point_bit[1][@n - 1 - (y - x)] & ((1u64 << y) - 1)
      return v == 0 ? -1 : y - (63 - v.leading_zeros_count.to_i)
    when 2
      v = @has_point_bit[2][y] & ((1u64 << x) - 1)
      return v == 0 ? -1 : x - (63 - v.leading_zeros_count.to_i)
    when 3
      v = @has_point_bit[3][y + x] & ~((1u64 << (y + 1)) - 1)
      return v == 0 ? -1 : v.trailing_zeros_count.to_i - y
    when 4
      v = @has_point_bit[0][x] & ~((1u64 << (y + 1)) - 1)
      return v == 0 ? -1 : v.trailing_zeros_count.to_i - y
    when 5
      v = @has_point_bit[1][@n - 1 - (y - x)] & ~((1u64 << (y + 1)) - 1)
      return v == 0 ? -1 : v.trailing_zeros_count.to_i - y
    when 6
      v = @has_point_bit[2][y] & ~((1u64 << (x + 1)) - 1)
      return v == 0 ? -1 : v.trailing_zeros_count.to_i - x
    when 7
      v = @has_point_bit[3][y + x] & ((1u64 << y) - 1)
      return v == 0 ? -1 : y - (63 - v.leading_zeros_count.to_i)
    end
    return -1
  end

  def add(rect)
    y, x = rect.y, rect.x
    @ps << Pos.new(y, x)
    @has_point_bit[0][x] |= 1u64 << y
    @has_point_bit[2][y] |= 1u64 << x
    @has_point_bit[1][@n - 1 - (y - x)] |= 1u64 << y
    @has_point_bit[3][y + x] |= 1u64 << y
    dir = rect.dir
    s0, s1 = rect.size0, rect.size1
    4.times do
      s0.times do
        @has_edge[y][x] |= 1 << dir
        y += DR[dir]
        x += DC[dir]
        @has_edge[y][x] |= 1 << (dir ^ 4)
      end
      dir = next_dir(dir)
      s0, s1 = s1, s0
    end
  end
end

def main
  solver = Solver.new
  best_res = RES_EMPTY
  PART.times do |i|
    res = solver.solve(START_TIME + TL * (i + 1) // PART)
    if res.score > best_res.score
      best_res = res
    end
  end
  puts best_res
  debug(STOPWATCH)
  debug(COUNTER)
  debug(best_res.rects.size / solver.n / solver.n)
  debug((best_res.score / solver.s * solver.n * solver.n / solver.m * 1_000_000).round.to_i)
end

main
