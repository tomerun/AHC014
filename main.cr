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
    @m.times do |i|
      @sxs[i], @sys[i] = read_line.split.map(&.to_i)
      @base_score += w(@sys[i], @sxs[i])
      @bbox_b = {@bbox_b, @sys[i]}.min
      @bbox_t = {@bbox_t, @sys[i]}.max
      @bbox_l = {@bbox_l, @sxs[i]}.min
      @bbox_r = {@bbox_r, @sxs[i]}.max
    end
    @has_point = Array(Array(Int32)).new(@n) { Array.new(@n, EMPTY) }
    @has_edge = Array(Array(Int32)).new(@n) { Array.new(@n, 0) }
    @s = 0
    @n.times do |i|
      @n.times do |j|
        @s += w(i, j)
      end
    end
    @prior_tilt = Array(Array(Int32)).new(@n) { Array.new(@n, 0) }
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
    while true
      if (turn & 0x1) == 0
        cur_time = Time.utc.to_unix_ms
        if cur_time >= timelimit
          debug("total_turn: #{turn}")
          break
        end
        ratio = (cur_time - begin_time) / total_time
        cooler = Math.exp(Math.log(INITIAL_COOLER) * (1.0 - ratio) + Math.log(FINAL_COOLER) * ratio)
      end
      @ps = orig_ps.dup
      res = solve_one(cur_res)
      if accept(res.score - cur_res.score, cooler)
        if res.score > best_res.score
          debug("score:#{res.score} turn:#{turn}")
          best_res = res
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
    @has_point.each { |row| row.fill(EMPTY) }
    @has_edge.each { |row| row.fill(0) }
    score = @base_score
    @m.times do |i|
      @has_point[@sys[i]][@sxs[i]] = -1
    end
    tilt_config = Array.new(4) { RND.next_int & 3 }
    (@n // 4).upto(@n * 3 // 4) do |i|
      (@n // 4).upto(@n * 3 // 4) do |j|
        if i < j
          if @n - 1 - i < j
            @prior_tilt[i][j] = 0x22 << ((i + (tilt_config[0] & 1)) % 2 * 2)
            @prior_tilt[i][j] |= 0x11 << ((i + j + (tilt_config[0] >> 1)) % 2 * 2)
          else
            @prior_tilt[i][j] = 0x22 << ((j + (tilt_config[1] & 1)) % 2 * 2)
            @prior_tilt[i][j] |= 0x11 << ((i + j + (tilt_config[1] >> 1)) % 2 * 2)
          end
        else
          if @n - 1 - i < j
            @prior_tilt[i][j] = 0x22 << ((j + (tilt_config[2] & 1)) % 2 * 2)
            @prior_tilt[i][j] |= 0x11 << ((i + j + (tilt_config[2] >> 1)) % 2 * 2)
          else
            @prior_tilt[i][j] = 0x22 << ((i + (tilt_config[3] & 1)) % 2 * 2)
            @prior_tilt[i][j] |= 0x11 << ((i + j + (tilt_config[3] >> 1)) % 2 * 2)
          end
        end
      end
    end
    STOPWATCH.stop("init")

    rects = [] of Rect
    if !prev_result.rects.empty?
      # 前回の結果からいくつかの四角とその依存元を保持する
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
          if rect.any? { |p| @has_point[p.y][p.x] == EMPTY }
            next
          end
          add(rect, rects.size)
          rects << rect
          score += w(rect.p0)
        end
      else
        prob_retain = RND.next_int(3) + 1
        prev_result.rects.size.times do |i|
          if (RND.next_int & 15) <= prob_retain
            rect = prev_result.rects[i]
            @has_point[rect.y][rect.x] = -1
          end
        end
        prev_result.rects.reverse_each do |rect|
          if @has_point[rect.y][rect.x] != EMPTY
            rects << rect
            score += w(rect.p0)
            rect.each do |p|
              @has_point[p.y][p.x] = -1
            end
          end
        end
        rects.reverse!
        rects.size.times { |i| add(rects[i], i) }
      end
      STOPWATCH.stop("retain")
      # debug("retain:#{rects.size} out of #{prev_result.rects.size}")
    end
    shuffle(@ps)
    si = 0
    initial_si = @ps.size
    STOPWATCH.start("find")
    while true
      found_rect = nil
      si.upto(@ps.size - 1) do |i|
        found_rect = find_rect(@ps[i].y, @ps[i].x, i < initial_si)
        break if found_rect
        si += 1
      end
      break if !found_rect
      add(found_rect, rects.size)
      rects << found_rect
      score += w(found_rect.p0)
    end
    STOPWATCH.stop("find")
    return Result.new(rects, score)
  end

  def find_rect(by, bx, initial)
    best_rect = nil
    best_val = INF
    if !initial
      dirs = @has_edge[by][bx] ^ 0xFF
      while dirs != 0
        dir0 = dirs.trailing_zeros_count
        dirs &= dirs - 1
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        # clockwise
        rect = find_rect_cw(by, bx, s0, dir0)
        if rect
          val = rect.size0 + rect.size1 + ((@prior_tilt[rect.y][rect.x] >> rect.dir) & 1)
          if val < best_val
            best_rect = rect
            best_val = val
          end
        end

        # counter-clockwise
        rect = find_rect_ccw(by, bx, s0, dir0)
        if rect
          val = rect.size0 + rect.size1 + ((@prior_tilt[rect.y][rect.x] >> rect.dir) & 1)
          if val < best_val
            best_rect = rect
            best_val = val
          end
        end

        # both sides
        rect = find_rect_both(by, bx, s0, dir0)
        if rect
          val = rect.size0 + rect.size1 + ((@prior_tilt[rect.y][rect.x] >> rect.dir) & 1)
          if val < best_val
            best_rect = rect
            best_val = val
          end
        end
      end
    else
      dirs = @has_edge[by][bx] ^ 0xFF
      while dirs != 0
        dir0 = dirs.trailing_zeros_count
        dirs &= dirs - 1
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        # clockwise
        rect = find_rect_cw(by, bx, s0, dir0)
        if rect
          val = rect.size0 + rect.size1 + ((@prior_tilt[rect.y][rect.x] >> rect.dir) & 1)
          if val < best_val
            best_rect = rect
            best_val = val
          end
        end
      end
    end
    return best_rect
  end

  def find_rect_cw(by, bx, s0, dir0)
    dir1 = next_dir(dir0)
    return nil if @has_edge[by][bx].bit(dir1) != 0
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    return nil if @has_edge[cy0][cx0].bit(dir1) != 0
    s1 = dist_nearest(cy0, cx0, dir1)
    return nil if s1 == -1
    cy1 = cy0 + DR[dir1] * s1
    cx1 = cx0 + DC[dir1] * s1
    cy2 = by + DR[dir1] * s1
    cx2 = bx + DC[dir1] * s1
    assert(cy1 == cy2 + DR[dir0] * s0)
    assert(cx1 == cx2 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_point[cy2][cx2] != EMPTY
    return nil if @has_edge[cy2][cx2].bit(dir0) != 0
    if (1...s0).any? do |i|
         y = cy2 + DR[dir0] * i
         x = cx2 + DC[dir0] * i
         @has_point[y][x] != EMPTY
       end
      return nil
    end
    if (1...s1).any? do |i|
         y = by + DR[dir1] * i
         x = bx + DC[dir1] * i
         @has_point[y][x] != EMPTY
       end
      return nil
    end
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
    cy1 = cy0 + DR[dir1] * s1
    cx1 = cx0 + DC[dir1] * s1
    cy2 = by + DR[dir1] * s1
    cx2 = bx + DC[dir1] * s1
    assert(cy1 == cy2 + DR[dir0] * s0)
    assert(cx1 == cx2 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_point[cy2][cx2] != EMPTY
    return nil if @has_edge[cy2][cx2].bit(dir0) != 0
    if (1...s0).any? do |i|
         y = cy2 + DR[dir0] * i
         x = cx2 + DC[dir0] * i
         @has_point[y][x] != EMPTY
       end
      return nil
    end
    if (1...s1).any? do |i|
         y = by + DR[dir1] * i
         x = bx + DC[dir1] * i
         @has_point[y][x] != EMPTY
       end
      return nil
    end
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
    cy1 = by + DR[dir1] * s1
    cx1 = bx + DC[dir1] * s1
    cy2 = cy0 + DR[dir1] * s1
    cx2 = cx0 + DC[dir1] * s1
    assert(cy2 == cy1 + DR[dir0] * s0)
    assert(cx2 == cx1 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_point[cy2][cx2] != EMPTY
    return nil if @has_edge[cy1][cx1].bit(dir0) != 0
    if (1...s0).any? do |i|
         y = cy1 + DR[dir0] * i
         x = cx1 + DC[dir0] * i
         @has_point[y][x] != EMPTY
       end
      return nil
    end
    if (1...s1).any? do |i|
         y = cy0 + DR[dir1] * i
         x = cx0 + DC[dir1] * i
         @has_point[y][x] != EMPTY
       end
      return nil
    end
    return Rect.new(Pos.new(cy2, cx2), s0, s1, dir0 ^ 4)
  end

  def dist_nearest(y, x, dir)
    s = 1
    while true
      y += DR[dir]
      x += DC[dir]
      return -1 if !inside(y) || !inside(x)
      if @has_point[y][x] != EMPTY
        return s
      end
      s += 1
    end
  end

  def add(rect, ridx)
    y, x = rect.y, rect.x
    @ps << Pos.new(y, x)
    @has_point[y][x] = ridx
    dir = rect.dir
    s0, s1 = rect.size0, rect.size1
    4.times do
      # TODO: bit演算でまとめて
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
  debug(best_res.rects.size / solver.n / solver.n)
  debug((best_res.score / solver.s * solver.n * solver.n / solver.m * 1_000_000).round.to_i)
end

main
