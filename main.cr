START_TIME = Time.utc.to_unix_ms
TL         = (ENV["TL"]? || 900).to_i
PART       = (ENV["PART"]? || 1).to_i
INF        = 1 << 28
EMPTY      = INF - 1
COUNTER    = Counter.new
STOPWATCH  = StopWatch.new
RND        = XorShift.new(2u64)
DR         = [-1, -1, 0, 1, 1, 1, 0, -1]
DC         = [0, -1, -1, -1, 0, 1, 1, 1]

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
    @m.times do |i|
      @sxs[i], @sys[i] = read_line.split.map(&.to_i)
    end
    @has_point = Array(Array(Int32)).new(@n) { Array.new(@n, EMPTY) }
    @has_edge = Array(Array(Int32)).new(@n) { Array.new(@n, 0) }
    @s = 0
    @n.times do |i|
      @n.times do |j|
        @s += w(i, j)
      end
    end
    @initial_points = Array(Array(Int32)).new(@n) { Array.new(@n, EMPTY) }
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
    orig_ps.sort_by! { |p| -w(p.y, p.x) }
    @ps = orig_ps.dup
    best_res = solve_one(RES_EMPTY)
    cur_res = best_res
    turn = 0
    tmp_orig_ps = orig_ps
    initial_cooler = 0.001
    final_cooler = 0.01
    cooler = initial_cooler
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
        cooler = Math.exp(Math.log(initial_cooler) * (1.0 - ratio) + Math.log(final_cooler) * ratio)
      end
      ch0 = -1
      ch1 = -1
      if turn < 100000
        tmp_orig_ps = orig_ps.sort_by { |p| -w(p.y, p.x) + RND.next_int(@n * @n // 10).to_i }
        @ps = tmp_orig_ps.dup
      else
        ch0 = RND.next_int(orig_ps.size)
        ch1 = RND.next_int(orig_ps.size - 1)
        ch1 += 1 if ch0 <= ch1
        @ps.clear
        @ps.concat(orig_ps)
        @ps[ch0], @ps[ch1] = @ps[ch1], @ps[ch0]
      end
      res = solve_one(cur_res)
      if accept(res.score - cur_res.score, cooler)
        if res.score > best_res.score
          best_res = res
          debug("score:#{res.score} turn:#{turn}")
        end
        cur_res = res
        # if turn < 100
        #   orig_ps = tmp_orig_ps
        # else
        #   orig_ps[ch0], orig_ps[ch1] = orig_ps[ch1], orig_ps[ch0]
        # end
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
    @has_point.each { |row| row.fill(EMPTY) }
    @has_edge.each { |row| row.fill(0) }
    score = 0
    @m.times do |i|
      @has_point[@sys[i]][@sxs[i]] = -1
      score += w(@sys[i], @sxs[i])
    end
    tilt_config = Array.new(4) { RND.next_int & 1 }
    @n.times do |i|
      @n.times do |j|
        if i < j
          if @n - 1 - i < j
            @prior_tilt[i][j] = (i + tilt_config[0]) % 2
          else
            @prior_tilt[i][j] = (j + tilt_config[1]) % 2
          end
        else
          if @n - 1 - i < j
            @prior_tilt[i][j] = (j + tilt_config[2]) % 2
          else
            @prior_tilt[i][j] = (i + tilt_config[3]) % 2
          end
        end
      end
    end

    rects = [] of Rect
    if !prev_result.rects.empty?
      # 前回の結果からいくつかの四角とその依存元を保持する
      prev_rects = prev_result.rects.sort_by { |r| w(r.p0) + RND.next_int(@n * @n // 4) }.last(40)
      retain_point = Array.new(@n, 0u64)
      prob_retain = RND.next_int(12) + 1
      prev_rects.size.times do |i|
        if (RND.next_int & 15) <= prob_retain
          rect = prev_rects[i]
          retain_point[rect.p0.y] |= 1u64 << rect.p0.x
        end
      end
      prev_result.rects.reverse_each do |rect|
        if retain_point[rect.p0.y].bit(rect.p0.x) != 0
          rects << rect
          score += w(rect.p0)
          rect.each do |p|
            retain_point[p.y] |= 1u64 << p.x
          end
        end
      end
      rects.reverse!
      rects.size.times { |i| add(rects[i], i) }
      # debug("retain:#{rects.size} out of #{prev_result.rects.size}")
    end
    @n.times do |i|
      @initial_points[i][0, @n] = @has_point[i]
    end
    while true
      found_rect = nil
      (@ps.size - 1).downto(0) do |i|
        found_rect = find_rect(@ps[i].y, @ps[i].x)
        break if found_rect
        @ps.pop
      end
      break if !found_rect
      add(found_rect[0], {found_rect[1], rects.size}.min)
      if found_rect[1] >= rects.size
        rects << found_rect[0]
      else
        # debug("insert #{found_rect[1]} / #{rects.size} #{found_rect[0]}")
        rects.insert(found_rect[1], found_rect[0])
        (found_rect[1] + 1).upto(rects.size - 1) do |i|
          r = rects[i]
          @has_point[r.p0.y][r.p0.x] = i
        end
      end
      score += w(found_rect[0].p0)
    end
    return Result.new(rects, score)
  end

  def find_rect(by, bx)
    if @initial_points[by][bx] != EMPTY
      8.times do |d|
        dir0 = ((d << 1) & 7 | (d >> 2)) ^ @prior_tilt[by][bx]
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        # clockwise
        rect = find_rect_cw(by, bx, s0, dir0)
        return rect if rect

        # counter-clockwise
        cy0 = by + DR[dir0] * s0
        cx0 = bx + DC[dir0] * s0
        rect = find_rect_cw(cy0, cx0, s0, dir0 ^ 4)
        return rect if rect

        # both sides
        rect = find_rect_both(by, bx, s0, dir0)
        return rect if rect
      end
    else
      8.times do |d|
        dir0 = ((d << 1) & 7 | (d >> 2)) ^ @prior_tilt[by][bx]
        next if @has_edge[by][bx].bit(next_dir(dir0)) != 0
        s0 = dist_nearest(by, bx, dir0)
        next if s0 == -1
        # clockwise
        rect = find_rect_cw(by, bx, s0, dir0)
        return rect if rect
      end
    end
    return nil
  end

  def find_rect_cw(by, bx, s0, dir0)
    dir1 = next_dir(dir0)
    return nil if @has_edge[by][bx].bit(dir1) != 0
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
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
    max_ridx = {@has_point[by][bx], @has_point[cy0][cx0], @has_point[cy1][cx1]}.max
    min_pi0 = s0 == 1 ? INF : (1...s0).min_of do |i|
      y = cy2 + DR[dir0] * i
      x = cx2 + DC[dir0] * i
      @has_edge[y][x].bit(dir0) == 0 ? @has_point[y][x] : -1
    end
    return nil if min_pi0 <= max_ridx
    min_pi1 = s1 == 1 ? INF : (1...s1).min_of do |i|
      y = by + DR[dir1] * i
      x = bx + DC[dir1] * i
      @has_edge[y][x].bit(dir1) == 0 ? @has_point[y][x] : -1
    end
    return nil if min_pi1 <= max_ridx
    if @has_edge[cy2][cx2] != 0 && (min_pi0 != INF || min_pi1 != INF)
      return nil
    end
    return Rect.new(Pos.new(cy2, cx2), s1, s0, dir1 ^ 4), {min_pi0, min_pi1}.min
  end

  def find_rect_both(by, bx, s0, dir0)
    dir1 = next_dir(dir0)
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    return nil if @has_edge[cy0][cx0].bit(dir1) != 0
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
    max_ridx = {@has_point[by][bx], @has_point[cy0][cx0], @has_point[cy1][cx1]}.max
    min_pi0 = s0 == 1 ? INF : (1...s0).min_of do |i|
      y = cy1 + DR[dir0] * i
      x = cx1 + DC[dir0] * i
      @has_edge[y][x].bit(dir0) == 0 ? @has_point[y][x] : -1
    end
    return nil if min_pi0 <= max_ridx
    min_pi1 = s1 == 1 ? INF : (1...s1).min_of do |i|
      y = cy0 + DR[dir1] * i
      x = cx0 + DC[dir1] * i
      @has_edge[y][x].bit(dir1) == 0 ? @has_point[y][x] : -1
    end
    return nil if min_pi1 <= max_ridx
    if @has_edge[cy2][cx2] != 0 && (min_pi0 != INF || min_pi1 != INF)
      return nil
    end
    return Rect.new(Pos.new(cy2, cx2), s0, s1, dir0 ^ 4), {min_pi0, min_pi1}.min
  end

  def dist_nearest(y, x, dir)
    return -1 if @has_edge[y][x].bit(dir) != 0
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
  debug([(best_res.score / solver.s * solver.n * solver.n / solver.m * 1_000_000).round.to_i, best_res.rects.size / solver.n / solver.n])
end

main
