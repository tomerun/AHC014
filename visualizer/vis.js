"use strict";
const input = document.getElementById("input")
const output = document.getElementById("output")
const update = document.getElementById("update")
const recolor = document.getElementById("recolor")
const frame = document.getElementById("frame")
const step = document.getElementById("step")
const canvas = document.getElementById("canvas")
const real_score = document.getElementById("score")
const raw_score = document.getElementById("raw_score")

function w(y, x, n) {
	const c = (n - 1) / 2
	return (y - c) ** 2 + (x - c) ** 2 + 1
}

class Point {
	constructor(y, x) {
		this.y = y
		this.x = x
	}
}

class Input {
	constructor(n, ps) {
		this.n = n
		this.ps = ps
		this.base_score = 0
		this.s = 0
		for (let i = 0; i < n; i++) {
			for (let j = 0; j < n; j++) {
				this.s += w(i, j, n)
			}
		}
		for (const p of ps) {
			this.base_score += w(p.y, p.x, n)
		}
	}
}

class Frame {
	constructor(input, rects) {
		this.rects = rects
	}

}

class Visualizer {
	constructor() {
		this.input = null
		this.frames = []
	}

	update() {
		this.frames = []
		const inputText = input.value.trim().split("\n")
		const [n, m] = inputText[0].split(" ").map((v) => parseInt(v))
		console.log("N:" + n + " M:" + m)
		const ps = inputText.slice(1, m + 1).map((line) => {
			const [x, y] = line.split(" ").map((v) => parseInt(v))
			return new Point(y, x)
		})
		this.input = new Input(n, ps)

		const outputText = output.value.trim().split("\n")
		let i = 0
		while (i < outputText.length) {
			const k = parseInt(outputText[i])
			const rects = []
			for	(let j = 1; j <= k; j++) {
				const elems = outputText[i + j].split(" ").map((v) => parseInt(v))
				rects.push([
					new Point(elems[1], elems[0]), new Point(elems[3], elems[2]), new Point(elems[5], elems[4]), new Point(elems[7], elems[6])
				])
			}
			i += k + 1
			this.frames.push(new Frame(this.input, rects))
		}
		frame.max = this.frames.length - 1
		frame.value = 0
		step.max = this.frames[0].rects.length
		step.value = step.max
		this.show(0, step.max)
	}

	show(frame_i, step_i) {
		const ctx = canvas.getContext('2d')
		const n = this.input.n
		const margin = 10
		const cell_size = (canvas.width - margin * 2) / (n - 1)
		console.log(`cell_size:${cell_size}`)
		ctx.clearRect(0, 0, canvas.width, canvas.height)
		ctx.font = "14px monospace"
		ctx.textAlign = "center"
		ctx.textBaseline = "middle"
		ctx.lineWidth = 1.0
		ctx.translate(margin, margin)

		ctx.beginPath()
		ctx.setLineDash([3, 3])
		ctx.strokeStyle = "#CCC"
		for (let i = 0; i < n; i++) {
			ctx.moveTo(0, i * cell_size)
			ctx.lineTo((n - 1) * cell_size, i * cell_size)
			ctx.moveTo(i * cell_size, 0)
			ctx.lineTo(i * cell_size, (n - 1) * cell_size)
		}
		ctx.stroke()
		ctx.setLineDash([])

		let score = this.input.base_score
		const f = this.frames[frame_i]
		ctx.lineWidth = 2
		f.rects.slice(0, step_i).forEach((rect) => {
			const col_r = Math.round(Math.random() * 150 + 50)
			const col_g = Math.round(Math.random() * 150 + 50)
			const col_b = Math.round(Math.random() * 150 + 50)
			ctx.strokeStyle = `rgb(${col_r}, ${col_g}, ${col_b})`
			ctx.beginPath()
			const dps = rect.map((p, i) => {
				const prev = rect[(i + 3) % 4]
				const next = rect[(i + 1) % 4]
				const min_y = Math.min(prev.y, next.y)
				const max_y = Math.max(prev.y, next.y)
				const min_x = Math.min(prev.x, next.x)
				const max_x = Math.max(prev.x, next.x)
				const my = max_y <= p.y ? 3 : min_y >= p.y ? -3 : 0
				const mx = max_x <= p.x ? -3 : min_x >= p.x ? 3 : 0
				return new Point((n - 1 - p.y) * cell_size + my, p.x * cell_size + mx)
			})
			ctx.moveTo(dps[3].x, dps[3].y)
			for (let p of dps) {
				ctx.lineTo(p.x, p.y)
			}
			ctx.stroke()
			score += w(rect[0].y, rect[0].x, this.input.n)
		})

		ctx.lineWidth = 1
		ctx.strokeStyle = 'black'
		f.rects.slice(0, step_i).forEach((rect, i) => {
			ctx.fillStyle = 'white'
			const p0 = rect[0]
			ctx.beginPath()
			ctx.arc(p0.x * cell_size, (n - 1 - p0.y) * cell_size, 10, 0, 2 * Math.PI)
			ctx.fill()
			ctx.stroke()

			const dy0 = -Math.sign(rect[1].y - p0.y) * 8
			const dx0 = Math.sign(rect[1].x - p0.x) * 8
			const dy1 = -Math.sign(rect[3].y - p0.y) * 8
			const dx1 = Math.sign(rect[3].x - p0.x) * 8
			const by = (n - 1 - p0.y) * cell_size + (dy0 == dy1 ? dy0 : dy0 + dy1)
			const bx = p0.x * cell_size + (dx0 == dx1 ? dx0 : dx0 + dx1)
			ctx.beginPath()
			ctx.moveTo(bx, by)
			ctx.lineTo(bx + dx0, by + dy0)
			ctx.moveTo(bx, by)
			ctx.lineTo(bx + dx1, by + dy1)
			ctx.stroke()

			ctx.fillStyle = 'black'
			const idxStr = i.toString()
			ctx.fillText(idxStr, p0.x * cell_size, (n - 1 - p0.y) * cell_size)
			// const metrics = ctx.measureText(idxStr)
			// ctx.fillText(idxStr, p0.x * cell_size - metrics.width / 2, (n - 1 - p0.y) * cell_size)
		})

		ctx.fillStyle = 'black'
		for (const p of this.input.ps) {
			ctx.beginPath()
			ctx.arc(p.x * cell_size, (n - 1 - p.y) * cell_size, 10, 0, 2 * Math.PI)
			ctx.fill()
		}

		ctx.resetTransform()

		real_score.innerText = Math.round(score / this.input.s * n * this.input.n / this.input.ps.length * 1000000)
		raw_score.innerText = score
	}
}

const visualizer = new Visualizer()

output.oninput = (event) => visualizer.update()
update.onclick = (event) => visualizer.update()
recolor.onclick = (event) => visualizer.show(frame.value, step.value)

frame.onchange = (event) => {
	const frame_i = event.target.value
	step.max = visualizer.frames[frame_i].rects.length
	step.value = step.max
	visualizer.show(frame_i, step.value)
}

step.onchange = (event) => {
	visualizer.show(frame.value, event.target.value)
}

