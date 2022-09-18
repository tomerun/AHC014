START_TIME = Time.utc.to_unix_ms
TL         = (ENV["TL"]? || 900).to_i
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
    @has_point = Array(UInt64).new(@n, 0u64)
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
    orig_ps = Array.new(@m) { |i| Pos.new(@sys[i], @sxs[i]) }
    orig_ps.sort_by! { |p| w(p.y, p.x) + RND.next_int(@n * @n // 4) }
    @ps = orig_ps.dup
    best_res = solve_one()
    turn = 0
    tmp_orig_ps = orig_ps
    while true
      if Time.utc.to_unix_ms > timelimit
        debug("turn:#{turn}")
        break
      end
      ch0 = -1
      ch1 = -1
      if turn < 100
        tmp_orig_ps = orig_ps.sort_by { |p| w(p.y, p.x) + RND.next_int(@n * @n // 4) }
        @ps = tmp_orig_ps.dup
      else
        ch0 = RND.next_int(orig_ps.size)
        ch1 = RND.next_int(orig_ps.size - 1)
        ch1 += 1 if ch0 <= ch1
        @ps.clear
        @ps.concat(orig_ps)
        @ps[ch0], @ps[ch1] = @ps[ch1], @ps[ch0]
      end
      res = solve_one()
      if res.score > best_res.score
        debug("score:#{res.score} turn:#{turn}")
        best_res = res
        if turn < 100
          orig_ps = tmp_orig_ps
        else
          orig_ps[ch0], orig_ps[ch1] = orig_ps[ch1], orig_ps[ch0]
        end
      end
      turn += 1
    end
    return best_res
  end

  def solve_one
    @has_point.fill(0u64)
    @has_edge.each { |row| row.fill(0) }
    score = 0
    @m.times do |i|
      @has_point[@sys[i]] |= 1u64 << @sxs[i]
      score += w(@sys[i], @sxs[i])
    end
    rects = [] of Rect
    while true
      found_rect = nil
      # (@ps.size - 1).downto(0) do |i|
      #   found_rect = find_rect(@ps[i].y, @ps[i].x, true)
      #   break if found_rect
      # end
      if !found_rect
        (@ps.size - 1).downto(0) do |i|
          found_rect = find_rect(@ps[i].y, @ps[i].x, false)
          break if found_rect
          @ps.pop
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
    8.times do |dir0|
      s0 = dist_nearest(by, bx, dir0)
      next if s0 == -1
      # clockwise
      rect = find_rect_cw(by, bx, s0, dir0, par_inside)
      return rect if rect

      # counter-clockwise
      cy0 = by + DR[dir0] * s0
      cx0 = bx + DC[dir0] * s0
      rect = find_rect_cw(cy0, cx0, s0, dir0 ^ 2, par_inside)
      return rect if rect

      # both sides
      rect = find_rect_both(by, bx, s0, dir0, par_inside)
      return rect if rect
    end
    return nil
  end

  def find_rect_cw(by, bx, s0, dir0, par_inside)
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    dir1 = next_dir(dir0)
    s1 = dist_nearest(cy0, cx0, dir1)
    return nil if s1 == -1
    cy1 = cy0 + DR[dir1] * s1
    cx1 = cx0 + DC[dir1] * s1
    cy2 = by + DR[dir1] * s1
    cx2 = bx + DC[dir1] * s1
    assert(cy1 == cy2 + DR[dir0] * s0)
    assert(cx1 == cx2 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_point[cy2].bit(cx2) != 0
    return nil if par_inside && dir0 >= 4 && (cy2 - @n // 2).abs < @n // 4 && (cx2 - @n // 2).abs < @n // 4
    # TODO: bit演算でまとめて
    return nil if @has_edge[cy2][cx2].bit(dir0) != 0 || (1...s0).any? do |j|
                    @has_point[cy2 + DR[dir0] * j].bit(cx2 + DC[dir0] * j) != 0
                  end
    return nil if @has_edge[by][bx].bit(dir1) != 0 || (1...s1).any? do |j|
                    @has_point[by + DR[dir1] * j].bit(bx + DC[dir1] * j) != 0
                  end
    return Rect.new(Pos.new(cy2, cx2), s0, s1, dir1 ^ 2)
  end

  def find_rect_both(by, bx, s0, dir0, par_inside)
    cy0 = by + DR[dir0] * s0
    cx0 = bx + DC[dir0] * s0
    dir1 = next_dir(dir0)
    s1 = dist_nearest(by, bx, dir1)
    return nil if s1 == -1
    cy1 = by + DR[dir1] * s1
    cx1 = bx + DC[dir1] * s1
    cy2 = cy0 + DR[dir1] * s1
    cx2 = cx0 + DC[dir1] * s1
    assert(cy2 == cy1 + DR[dir0] * s0)
    assert(cx2 == cx1 + DC[dir0] * s0)
    return nil if !inside(cy2) || !inside(cx2)
    return nil if @has_point[cy2].bit(cx2) != 0
    return nil if par_inside && dir0 >= 4 && (cy2 - @n // 2).abs < @n // 4 && (cx2 - @n // 2).abs < @n // 4
    # TODO: bit演算でまとめて
    return nil if @has_edge[cy1][cx1].bit(dir0) != 0 || (1...s0).any? do |j|
                    @has_point[cy1 + DR[dir0] * j].bit(cx1 + DC[dir0] * j) != 0
                  end
    return nil if @has_edge[cy0][cx0].bit(dir1) != 0 || (1...s1).any? do |j|
                    @has_point[cy0 + DR[dir1] * j].bit(cx0 + DC[dir1] * j) != 0
                  end
    return Rect.new(Pos.new(cy2, cx2), s1, s0, dir0 ^ 2)
  end

  def dist_nearest(y, x, dir)
    return -1 if @has_edge[y][x].bit(dir) != 0
    s = 1
    while true
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
    @has_point[y] |= 1u64 << x
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
  best_res = solver.solve(START_TIME + TL)
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
