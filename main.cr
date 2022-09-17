START_TIME = Time.utc.to_unix_ms
TL         = 900
INF        = 1 << 28
COUNTER    = Counter.new
STOPWATCH  = StopWatch.new
RND        = XorShift.new(2u64)
DR         = [-1, 0, 1, 0, -1, 1, 1, -1]
DC         = [0, -1, 0, 1, -1, -1, 1, 1]

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
  getter :p0, :size0, :size1, :dir

  def initialize(@p0 : Pos, @size0 : Int32, @size1 : Int32, @dir : Int32)
  end

  def as_coords
    dy = DR[@dir]
    dx = DC[@dir]
    ps = [p0.x, p0.y, p0.x + dx * @size1, p0.y + dy * @size1]
    dy, dx = dx * -1, dy
    ps << ps[-2] + dx * @size0
    ps << ps[-2] + dy * @size0
    dy, dx = dx * -1, dy
    ps << ps[-2] + dx * @size1
    ps << ps[-2] + dy * @size1
    return ps.join(" ")
  end

  def y
    @p0.y
  end

  def x
    @p0.x
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
  return ((d + 1) & 3) | (d & 4)
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
    @has_point = Array(Int32).new(@n, 0)
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

  def solve(timelimit)
    @ps = Array.new(@m) { |i| Pos.new(@sys[i], @sxs[i]) }
    @ps.sort_by! { |p| w(p.y, p.x) + RND.next_int(@n * @n // 4) }
    shuffle(@ps)
    @has_point.fill(0)
    @has_edge.each { |row| row.fill(0) }
    score = 0
    @m.times do |i|
      @has_point[@sys[i]] |= 1 << @sxs[i]
      score += w(@sys[i], @sxs[i])
    end
    rects = [] of Rect
    while true
      found_rect = nil
      @ps.size.times do |i|
        found_rect = find_rect(@ps[@ps.size - 1 - i].y, @ps[@ps.size - 1 - i].x, true)
        break if found_rect
      end
      if !found_rect
        @ps.size.times do |i|
          found_rect = find_rect(@ps[@ps.size - 1 - i].y, @ps[@ps.size - 1 - i].x, false)
          break if found_rect
        end
      end
      break if !found_rect
      rects << found_rect
      add(found_rect)
      score += w(found_rect.p0)
    end
    return Result.new(rects, score)
  end

  def find_rect(by, bx, par_inside)
    8.times do |dir0| # TODO: 逆方向も見ることにすれば半分でいい
      dir1 = next_dir(dir0)
      s0 = dist_nearest(by, bx, dir0)
      next if s0 == -1
      cy0 = by + DR[dir0] * s0
      cx0 = bx + DC[dir0] * s0
      s1 = dist_nearest(cy0, cx0, dir1)
      next if s1 == -1
      cy1 = cy0 + DR[dir1] * s1
      cx1 = cx0 + DC[dir1] * s1
      cy2 = by + DR[dir1] * s1
      cx2 = bx + DC[dir1] * s1
      assert(cy1 == cy2 + DR[dir0] * s0)
      assert(cx1 == cx2 + DC[dir0] * s0)
      next if !inside(cy2) || !inside(cx2)
      next if @has_point[cy2].bit(cx2) != 0
      next if par_inside && dir0 >= 4 && (cy2 - @n // 2).abs < @n // 4 && (cx2 - @n // 2).abs < @n // 4
      # TODO: bit演算でまとめて
      next if s0.times.any? do |j|
                @has_edge[cy2 + DR[dir0] * j][cx2 + DC[dir0] * j].bit(dir0) != 0 ||
                (j != 0 && @has_point[cy2 + DR[dir0] * j].bit(cx2 + DC[dir0] * j) != 0)
              end
      next if s1.times.any? do |j|
                @has_edge[by + DR[dir1] * j][bx + DC[dir1] * j].bit(dir1) != 0 ||
                (j != 0 && @has_point[by + DR[dir1] * j].bit(bx + DC[dir1] * j) != 0)
              end
      return Rect.new(Pos.new(cy2, cx2), s0, s1, dir1 ^ 2)
    end
    return nil
  end

  def dist_nearest(y, x, dir)
    s = 1
    while true
      return -1 if @has_edge[y][x].bit(dir) != 0
      y += DR[dir]
      x += DC[dir]
      return -1 if !inside(y) || !inside(x)
      if @has_point[y].bit(x) != 0
        return s
      end
      s += 1
    end
  end

  def add(rect)
    y, x = rect.y, rect.x
    @ps << Pos.new(y, x)
    # pos = RND.next_int(@ps.size)
    # @ps[pos], @ps[-1] = @ps[-1], @ps[pos]
    @has_point[y] |= 1 << x
    dir = rect.dir
    s0, s1 = rect.size1, rect.size0
    4.times do
      # TODO: bit演算でまとめて
      s0.times do
        @has_edge[y][x] |= 1 << dir
        y += DR[dir]
        x += DC[dir]
        @has_edge[y][x] |= 1 << (dir ^ 2)
      end
      dir = next_dir(dir)
      s0, s1 = s1, s0
    end
  end
end

def main
  solver = Solver.new
  best_res = RES_EMPTY
  turn = 0
  while true
    if Time.utc.to_unix_ms > START_TIME + TL
      debug("turn:#{turn}")
      break
    end
    res = solver.solve(START_TIME + TL)
    if res.score > best_res.score
      debug("score:#{res.score} turn:#{turn}")
      best_res = res
    end
    turn += 1
  end
  # part = 1
  # part.times do |i|
  #   res = solver.solve(START_TIME + TL * (i + 1) // part)
  #   if res.score > best_res.score
  #     best_res = res
  #   end
  # end
  puts best_res
  debug((best_res.score / solver.s * solver.n * solver.n / solver.m * 1_000_000).round.to_i)
end

main
