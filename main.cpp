#include <algorithm>
#include <utility>
#include <vector>
#include <iostream>
#include <array>
#include <numeric>
#include <memory>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <cmath>
#include <sys/time.h>

#ifdef LOCAL
#ifndef NDEBUG
#define MEASURE_TIME
#define DEBUG
#endif
#else
#define NDEBUG
// #define DEBUG
#endif
#include <cassert>

using namespace std;
using u8=uint8_t;
using u16=uint16_t;
using u32=uint32_t;
using u64=uint64_t;
using i64=int64_t;
using ll=int64_t;
using ull=uint64_t;
using vi=vector<int>;
using vvi=vector<vi>;

namespace {

#ifdef LOCAL
constexpr ll TL = 900;
#else
constexpr ll TL = 900;
#endif

inline ll get_time() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  ll result =  tv.tv_sec * 1000LL + tv.tv_usec / 1000LL;
  return result;
}

const ll start_time = get_time(); // msec

inline ll get_elapsed_msec() {
  return get_time() - start_time;
}

inline bool reach_time_limit() {
  return get_elapsed_msec() >= TL;
}

struct XorShift {
  uint32_t x,y,z,w;
  static const double TO_DOUBLE;

  XorShift() {
    x = 123456789;
    y = 362436069;
    z = 521288629;
    w = 88675123;
  }

  uint32_t nextUInt(uint32_t n) {
    uint32_t t = x ^ (x << 11);
    x = y;
    y = z;
    z = w;
    w = (w ^ (w >> 19)) ^ (t ^ (t >> 8));
    return w % n;
  }

  uint32_t nextUInt() {
    uint32_t t = x ^ (x << 11);
    x = y;
    y = z;
    z = w;
    return w = (w ^ (w >> 19)) ^ (t ^ (t >> 8));
  }

  double nextDouble() {
    return nextUInt() * TO_DOUBLE;
  }
};
const double XorShift::TO_DOUBLE = 1.0 / (1LL << 32);

struct Counter {
  vector<ull> cnt;

  void add(int i) {
    if (i >= cnt.size()) {
      cnt.resize(i+1);
    }
    ++cnt[i];
  }

  void print() {
    cerr << "counter:[";
    for (int i = 0; i < cnt.size(); ++i) {
      cerr << cnt[i] << ", ";
      if (i % 10 == 9) cerr << endl;
    }
    cerr << "]" << endl;
  }
};

struct Timer {
  vector<ull> at;
  vector<ull> sum;

  void start(int i) {
    if (i >= at.size()) {
      at.resize(i+1);
      sum.resize(i+1);
    }
    at[i] = get_time();
  }

  void stop(int i) {
    sum[i] += get_time() - at[i];
  }

  void print() {
    cerr << "timer:[";
    for (int i = 0; i < at.size(); ++i) {
      cerr << sum[i] << ", ";
      if (i % 10 == 9) cerr << endl;
    }
    cerr << "]" << endl;
  }
};

}

#ifdef MEASURE_TIME
#define START_TIMER(i) (timer.start(i))
#define STOP_TIMER(i) (timer.stop(i))
#define PRINT_TIMER() (timer.print())
#define ADD_COUNTER(i) (counter.add(i))
#define PRINT_COUNTER() (counter.print())
#else
#define START_TIMER(i)
#define STOP_TIMER(i)
#define PRINT_TIMER()
#define ADD_COUNTER(i)
#define PRINT_COUNTER()
#endif

#ifdef DEBUG
#define debug(format, ...) fprintf(stderr, format, __VA_ARGS__)
#define debugStr(str) fprintf(stderr, str)
#define debugln() fprintf(stderr, "\n")
#else
#define debug(format, ...)
#define debugStr(str)
#define debugln()
#endif

template<class T>
constexpr inline T sq(T v) { return v * v; }

void debug_vec(const vi& vec) {
  debugStr("[");
  for (int i = 0; i < vec.size(); ++i) {
    debug("%d ", vec[i]);
  }
  debugStr("]");
}

XorShift rnd;
Timer timer;
Counter counter;

//////// end of template ////////

constexpr array<int, 8> DR = {-1, -1, 0, 1, 1, 1, 0, -1};
constexpr array<int, 8> DC = {0, -1, -1, -1, 0, 1, 1, 1};
constexpr double INITIAL_COOLER = 0.0003;
constexpr double FINAL_COOLER = 0.0100;

int N, M, S;
vi XS, YS;
array<array<uint64_t, 121>, 4> initial_has_point_bit;
array<array<uint64_t, 121>, 4> has_point_bit;
array<uint64_t, 121>& has_point = has_point_bit[2];
array<array<int, 61>, 61> has_edge;

template<class T>
void shuffle(vector<T>& v) {
  for (int i = 0; i + 1 < v.size(); ++i) {
    int pos = rnd.nextUInt(v.size() - i) + i;
    swap(v[i], v[pos]);
  }
}

inline int dist2(int y0, int x0, int y1, int x1) {
  return (y0 - y1) * (y0 - y1) + (x0 - x1) * (x0 - x1);
}

inline int w(int y, int x) {
  return dist2(y, x, N / 2, N / 2) + 1;
}

inline bool inside(int p) {
  return 0 <= p && p < N;
}

struct Pos {
  int y, x;
};

struct Rect {
  Pos p0;
  int size0, size1, dir;

  Rect(Pos p0_, int size0_, int size1_, int dir_) : p0(p0_), size0(size0_), size1(size1_), dir(dir_) {}

  Rect(int y_, int x_, int size0_, int size1_, int dir_) : size0(size0_), size1(size1_), dir(dir_) {
    p0.y = y_;
    p0.x = x_;
  }

  int y() const {
    return p0.y;
  }

  int x() const {
    return p0.x;
  }
};

const Rect RECT_EMPTY(0, 0, 0, 0, 0);

struct Result {
  vector<Rect> rects;
  int score;

  Result(const vector<Rect>& rects_, int score_) : rects(rects_), score(score_) {}
};

constexpr int next_dir(int d) {
  return (d + 2) & 7;
}

void verify(const vector<Rect>& rects) {
  array<array<bool, 61>, 61> exist_point = {};
  array<array<array<bool, 8>, 61>, 61> exist_edge = {};
  for (int i = 0; i < M; ++i) {
    exist_point[YS[i]][XS[i]] = true;
  }
  for (int i = 0; i < rects.size(); ++i) {
    const Rect& rect = rects[i];
    assert(!exist_point[rect.y()][rect.x()]);
    exist_point[rect.y()][rect.x()] = true;
    int s0 = rect.size0;
    int s1 = rect.size1;
    int dir = rect.dir;
    int y = rect.y();
    int x = rect.x();
    for (int j = 0; j < 4; ++j) {
      exist_edge[y][x][dir] = true;
      exist_edge[y + DR[dir]][x + DC[dir]][dir ^ 4] = true;
      for (int k = 0; k < s0 - 1; ++k) {
        y += DR[dir];
        x += DC[dir];
        assert(!exist_point[y][x]);
        assert(!exist_edge[y][x][dir]);
        exist_edge[y][x][dir] = true;
        exist_edge[y + DR[dir]][x + DC[dir]][dir ^ 4] = true;
      }
      y += DR[dir];
      x += DC[dir];
      assert(exist_point[y][x]);
      swap(s0, s1);
      dir = next_dir(dir);
    }
  }
}

// maximize
bool accept(int diff, double cooler) {
  if (diff >= 0) return true;
  double v = diff * cooler;
  if (v < -10) return false;
  return rnd.nextDouble() < exp(v);
}

struct Solver {
  int base_score;
  int bbox_b, bbox_t, bbox_l, bbox_r;
  vector<Pos> ps;

  Solver() {
    base_score = 0;
    bbox_b = N;
    bbox_t = 0;
    bbox_l = N;
    bbox_r = 0;
    for (int i = 0; i < M; ++i) {
      base_score += w(YS[i], XS[i]);
      bbox_b = min(bbox_b, YS[i]);
      bbox_t = max(bbox_t, YS[i]);
      bbox_l = min(bbox_l, XS[i]);
      bbox_r = max(bbox_r, XS[i]);
      initial_has_point_bit[0][XS[i]] |= 1ull << YS[i];
      initial_has_point_bit[2][YS[i]] |= 1ull << XS[i];
      initial_has_point_bit[1][N - 1 - (YS[i] - XS[i])] |= 1ull << YS[i];
      initial_has_point_bit[3][YS[i] + XS[i]] |= 1ull << YS[i];
    }
  }

  Result solve(int64_t timelimit) {
    vector<Pos> orig_ps;
    for (int i = 0; i < M; ++i) {
      Pos pos = {YS[i], XS[i]};
      orig_ps.push_back(pos);
    }
    ps = orig_ps;
    Result best_res = solve_one(Result(vector<Rect>(), 0));
    Result cur_res = best_res;
    int turn = 0;
    double cooler = INITIAL_COOLER;
    const auto begin_time = get_time();
    const auto total_time = timelimit - begin_time;
    int last_update_turn = 0;
    while (true) {
      if ((turn & 0xF) == 0) {
        auto cur_time = get_time();
        if (cur_time >= timelimit) {
          debug("total_turn:%d\n", turn);
          break;
        }
        const double ratio = 1.0 * (cur_time - begin_time) / total_time;
        cooler = exp(log(INITIAL_COOLER) * (1.0 - ratio) + log(FINAL_COOLER) * ratio);
        if (turn > last_update_turn + 5000) {
          cur_res = best_res;
          last_update_turn = turn;
          debug("revert turn:%d\n", turn);
        }
      }
      ps = orig_ps;
      Result res = solve_one(cur_res);
      if (accept(res.score - cur_res.score, cooler)) {
        if (res.score > best_res.score) {
          debug("best_score:%d turn:%d\n", res.score, turn);
          best_res = res;
          last_update_turn = turn;
        }
        swap(cur_res.rects, res.rects);
        cur_res.score = res.score;
      }
      turn++;
    }
#ifdef DEBUG
    verify(best_res.rects);
#endif
    return best_res;
  }

  Result solve_one(const Result& prev_result) {
    START_TIMER(0);
    has_point_bit[0] = initial_has_point_bit[0];
    has_point_bit[1] = initial_has_point_bit[1];
    has_point_bit[2] = initial_has_point_bit[2];
    has_point_bit[3] = initial_has_point_bit[3];
    for (int i = 0; i < N; ++i) {
      fill(has_edge[i].begin(), has_edge[i].begin() + N, 0);
    }
    int score = base_score;
    STOP_TIMER(0);
    static vector<Rect> rects;
    rects.clear();
    if (!prev_result.rects.empty()) {
      START_TIMER(1);
      if ((rnd.nextUInt() & 0x1F) == 0) {
        Pos rm_pos = prev_result.rects[rnd.nextUInt(prev_result.rects.size())].p0;
        const int rm_b = rm_pos.y - rnd.nextUInt(5);
        const int rm_t = rm_pos.y + rnd.nextUInt(5);
        const int rm_l = rm_pos.x - rnd.nextUInt(5);
        const int rm_r = rm_pos.x + rnd.nextUInt(5);
        for (const Rect& rect : prev_result.rects) {
          if (rm_b <= rect.y() && rect.y() <= rm_t && rm_l <= rect.x() && rect.x() <= rm_r) {
            continue;
          }
          int y = rect.y() + DR[rect.dir] * rect.size0;
          int x = rect.x() + DC[rect.dir] * rect.size0;
          if ((has_point[y] & (1ull << x)) == 0) continue;
          y += -DC[rect.dir] * rect.size1;
          x += DR[rect.dir] * rect.size1;
          if ((has_point[y] & (1ull << x)) == 0) continue;
          y += -DR[rect.dir] * rect.size0;
          x += -DC[rect.dir] * rect.size0;
          if ((has_point[y] & (1ull << x)) == 0) continue;
          add(rect);
          rects.push_back(rect);
          score += w(rect.y(), rect.x());
        }
      } else {
        const int prob_keep = rnd.nextUInt(3) + 1;
        for (auto itr = prev_result.rects.rbegin(); itr != prev_result.rects.rend(); ++itr) {
          const Rect& rect = *itr;
          if ((has_point[rect.y()] & (1ull << rect.x())) || (rnd.nextUInt() & 0xF) <= prob_keep) {
            add(rect);
            rects.push_back(rect);
            score += w(rect.y(), rect.x());
            int y = rect.y() + DR[rect.dir] * rect.size0;
            int x = rect.x() + DC[rect.dir] * rect.size0;
            has_point[y] |= (1ull << x);
            y += -DC[rect.dir] * rect.size1;
            x += DR[rect.dir] * rect.size1;
            has_point[y] |= (1ull << x);
            y += -DR[rect.dir] * rect.size0;
            x += -DC[rect.dir] * rect.size0;
            has_point[y] |= (1ull << x);
          }
        }
        reverse(rects.begin(), rects.end());
      }
      STOP_TIMER(1);
    }
    shuffle(ps);
    START_TIMER(2);
    const int initial_si = ps.size();
    for (int i = 0; i < initial_si; ++i) {
      const int by = ps[i].y;
      const int bx = ps[i].x;
      int dirs = ~(has_edge[by][bx] | (has_edge[by][bx] >> 2) | (has_edge[by][bx] << 6)) & 0xFF;
      while (dirs != 0) {
        int dir0 = __builtin_ctzll(dirs);
        dirs &= dirs - 1;
        int s0 = dist_nearest(by, bx, dir0);
        if (s0 == -1) continue;
        Rect rect = find_rect_cw(by, bx, s0, dir0);
        if (rect.size0 == 0) continue;
        add(rect);
        rects.push_back(rect);
        score += w(rect.y(), rect.x());
        dirs &= ~has_edge[by][bx];
      }
    }
    int pi = initial_si;
    while (pi < ps.size()) {
      const int by = ps[pi].y;
      const int bx = ps[pi].x;
      int dirs = ~(has_edge[by][bx] | (has_edge[by][bx] >> 2) | (has_edge[by][bx] << 6)) & 0xFF;
      while (dirs != 0) {
        const int dir0 = __builtin_ctz(dirs);
        dirs &= dirs - 1;
        const int s0 = dist_nearest(by, bx, dir0);
        if (s0 == -1) continue;
        Rect rect = find_rect_cw(by, bx, s0, dir0);
        if (rect.size0 == 0) {
          rect = find_rect_both(by, bx, s0, dir0);
        }
        if (rect.size0 > 0) {
          add(rect);
          rects.push_back(rect);
          score += w(rect.y(), rect.x());
          dirs &= ~has_edge[by][bx];
        }
      }
      dirs = ~(has_edge[by][bx] | (has_edge[by][bx] >> 6) | (has_edge[by][bx] << 2)) & 0xFF;
      while (dirs != 0) {
        const int dir0 = __builtin_ctz(dirs);
        dirs &= dirs - 1;
        const int s0 = dist_nearest(by, bx, dir0);
        if (s0 == -1) continue;
        Rect rect = find_rect_ccw(by, bx, s0, dir0);
        if (rect.size0 > 0) {
          add(rect);
          rects.push_back(rect);
          score += w(rect.y(), rect.x());
          dirs &= ~has_edge[by][bx];
        }
      }
      pi += 1;
    }
    STOP_TIMER(2);
    return Result(rects, score);
  }

  Rect find_rect_cw(int by, int bx, int s0, int dir0) {
    const int dir1 = next_dir(dir0);
    if (has_edge[by][bx] & (1ull << dir1)) return RECT_EMPTY;
    const int cy0 = by + DR[dir0] * s0;
    const int cx0 = bx + DC[dir0] * s0;
    if (has_edge[cy0][cx0] & (1ull << dir1)) return RECT_EMPTY;
    const int s1 = dist_nearest(cy0, cx0, dir1);
    if (s1 == -1) return RECT_EMPTY;
    const int s11 = dist_nearest(by, bx, dir1);
    if ((0 < s11) && (s11 <= s1)) return RECT_EMPTY;
    const int cy2 = by + DR[dir1] * s1;
    const int cx2 = bx + DC[dir1] * s1;
    assert(cy0 + DR[dir1] * s1 == cy2 + DR[dir0] * s0);
    assert(cx0 + DC[dir1] * s1 == cx2 + DC[dir0] * s0);
    if (!inside(cy2) || !inside(cx2)) return RECT_EMPTY;
    if (has_edge[cy2][cx2] & (1ull << dir0)) return RECT_EMPTY;
    if (dist_nearest(cy2, cx2, dir0) != s0) return RECT_EMPTY;
    return Rect(cy2, cx2, s1, s0, dir1 ^ 4);
  }

  Rect find_rect_ccw(int by, int bx, int s0, int dir0) {
    const int dir1 = next_dir(dir0) ^ 4;
    if (has_edge[by][bx] & (1ull << dir1)) return RECT_EMPTY;
    const int cy0 = by + DR[dir0] * s0;
    const int cx0 = bx + DC[dir0] * s0;
    if (has_edge[cy0][cx0] & (1ull << dir1)) return RECT_EMPTY;
    const int s1 = dist_nearest(cy0, cx0, dir1);
    if (s1 == -1) return RECT_EMPTY;
    const int s11 = dist_nearest(by, bx, dir1);
    if ((0 < s11) && (s11 <= s1)) return RECT_EMPTY;
    const int cy2 = by + DR[dir1] * s1;
    const int cx2 = bx + DC[dir1] * s1;
    assert(cy0 + DR[dir1] * s1 == cy2 + DR[dir0] * s0);
    assert(cx0 + DC[dir1] * s1 == cx2 + DC[dir0] * s0);
    if (!inside(cy2) || !inside(cx2)) return RECT_EMPTY;
    if (has_edge[cy2][cx2] & (1ull << dir0)) return RECT_EMPTY;
    if (dist_nearest(cy2, cx2, dir0) != s0) return RECT_EMPTY;
    return Rect(cy2, cx2, s0, s1, dir0);
  }

  Rect find_rect_both(int by, int bx, int s0, int dir0) {
    const int dir1 = next_dir(dir0);
    if (has_edge[by][bx] & (1ull << dir1)) return RECT_EMPTY;
    const int cy0 = by + DR[dir0] * s0;
    const int cx0 = bx + DC[dir0] * s0;
    if (has_edge[cy0][cx0] & (1ull << dir1)) return RECT_EMPTY;
    const int s1 = dist_nearest(by, bx, dir1);
    if (s1 == -1) return RECT_EMPTY;
    const int s11 = dist_nearest(cy0, cx0, dir1);
    if ((0 < s11) && (s11 <= s1)) return RECT_EMPTY;
    const int cy1 = by + DR[dir1] * s1;
    const int cx1 = bx + DC[dir1] * s1;
    const int cy2 = cy0 + DR[dir1] * s1;
    const int cx2 = cx0 + DC[dir1] * s1;
    assert(cy2 == cy1 + DR[dir0] * s0);
    assert(cx2 == cx1 + DC[dir0] * s0);
    if (!inside(cy2) || !inside(cx2)) return RECT_EMPTY;
    if (has_edge[cy1][cx1] & (1ull << dir0)) return RECT_EMPTY;
    if (dist_nearest(cy2, cx2, dir0 ^ 4) != s0) return RECT_EMPTY;
    return Rect(cy2, cx2, s0, s1, dir0 ^ 4);
  }

  int dist_nearest(int y, int x, int dir) {
    switch (dir) {
      case 0: {
        const uint64_t v = has_point_bit[0][x] & ((1ull << y) - 1);
        return v == 0 ? -1 : y - (63 - __builtin_clzll(v));
      }
      case 1: {
        const uint64_t v = has_point_bit[1][N - 1 - (y - x)] & ((1ull << y) - 1);
        return v == 0 ? -1 : y - (63 - __builtin_clzll(v));
      }
      case 2: {
        const uint64_t v = has_point_bit[2][y] & ((1ull << x) - 1);
        return v == 0 ? -1 : x - (63 - __builtin_clzll(v));
      }
      case 3: {
        const uint64_t v = has_point_bit[3][y + x] & ~((1ull << (y + 1)) - 1);
        return v == 0 ? -1 : __builtin_ctzll(v) - y;
      }
      case 4: {
        const uint64_t v = has_point_bit[0][x] & ~((1ull << (y + 1)) - 1);
        return v == 0 ? -1 : __builtin_ctzll(v) - y;
      }
      case 5: {
        const uint64_t v = has_point_bit[1][N - 1 - (y - x)] & ~((1ull << (y + 1)) - 1);
        return v == 0 ? -1 : __builtin_ctzll(v) - y;
      }
      case 6: {
        const uint64_t v = has_point_bit[2][y] & ~((1ull << (x + 1)) - 1);
        return v == 0 ? -1 : __builtin_ctzll(v) - x;
      }
      case 7:
      default: {
        const uint64_t v = has_point_bit[3][y + x] & ((1ull << y) - 1);
        return v == 0 ? -1 : y - (63 - __builtin_clzll(v));
      }
    }
  }

  void add(const Rect& rect) {
    int y = rect.y();
    int x = rect.x();
    ps.push_back(rect.p0);
    has_point_bit[0][x] |= 1ull << y;
    has_point_bit[2][y] |= 1ull << x;
    has_point_bit[1][N - 1 - (y - x)] |= 1ull << y;
    has_point_bit[3][y + x] |= 1ull << y;
    int dir = rect.dir;
    int s0 = rect.size0;
    int s1 = rect.size1;
    for (int i = 0; i < 4; ++i) {
      for (int j = 0; j < s0; ++j) {
        has_edge[y][x] |= 1 << dir;
        y += DR[dir];
        x += DC[dir];
        has_edge[y][x] |= 1 << (dir ^ 4);
      }
      dir = next_dir(dir);
      swap(s0, s1);
    }
  }

};

int main() {
  scanf("%d %d", &N, &M);
  YS.resize(M);
  XS.resize(M);
  for (int i = 0; i < M; ++i) {
    scanf("%d %d", &XS[i], &YS[i]);
  }
  for (int i = 0; i < N; ++i) {
    for (int j = 0; j < N; ++j) {
      S += w(i, j);
    }
  }
  debug("N:%d M:%d S:%d\n", N, M, S);

  auto solver = unique_ptr<Solver>(new Solver());
  Result res = solver->solve(start_time + TL);
  printf("%d\n", (int)res.rects.size());
  for (const Rect& rect : res.rects) {
    int dy = DR[rect.dir];
    int dx = DC[rect.dir];
    int y = rect.y();
    int x = rect.x();
    printf("%d %d ", x, y);
    y += dy * rect.size0;
    x += dx * rect.size0;
    swap(dy, dx);
    dy *= -1;
    printf("%d %d ", x, y);
    y += dy * rect.size1;
    x += dx * rect.size1;
    swap(dy, dx);
    dy *= -1;
    printf("%d %d ", x, y);
    y += dy * rect.size0;
    x += dx * rect.size0;
    printf("%d %d\n", x, y);
  }
  fflush(stdout);
  PRINT_TIMER();
  debug("ratio:%.3f\n", 1.0 * res.rects.size() / (N * N));
  debug("%d\n", (int)(1e6 * res.score / S * N * N / M + 0.5));
}
