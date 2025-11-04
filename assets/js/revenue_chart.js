export const RevenueChart = {
  mounted() {
    this.chart = null
    this.renderChart()
  },

  updated() {
    this.renderChart()
  },

  renderChart() {
    const canvas = this.el
    const dataStr = canvas.getAttribute("data-chart-data")
    if (!dataStr) return

    const data = JSON.parse(dataStr)
    
    // Destroy existing chart if it exists
    if (this.chart) {
      this.chart.destroy()
    }

    // Prepare chart data
    const labels = data.map(item => item.date)
    const revenue = data.map(item => parseFloat(item.revenue || 0))

    // Use Chart.js if available, otherwise render simple SVG
    if (window.Chart) {
      const ctx = canvas.getContext("2d")
      this.chart = new Chart(ctx, {
        type: "line",
        data: {
          labels: labels,
          datasets: [{
            label: "Revenue",
            data: revenue,
            borderColor: "rgb(59, 130, 246)",
            backgroundColor: "rgba(59, 130, 246, 0.1)",
            tension: 0.4,
            fill: true
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              display: false
            },
            tooltip: {
              callbacks: {
                label: function(context) {
                  return "$" + context.parsed.y.toFixed(2)
                }
              }
            }
          },
          scales: {
            y: {
              beginAtZero: true,
              ticks: {
                callback: function(value) {
                  return "$" + value.toFixed(0)
                }
              }
            }
          }
        }
      })
    } else {
      // Fallback: render simple text representation
      canvas.parentElement.innerHTML = `
        <div class="p-4">
          <p class="text-sm text-gray-500 mb-2">Chart.js not loaded. Install with: npm install chart.js</p>
          <div class="space-y-1">
            ${data.map(item => `
              <div class="flex justify-between text-sm">
                <span>${item.date}</span>
                <span class="font-medium">$${parseFloat(item.revenue || 0).toFixed(2)}</span>
              </div>
            `).join("")}
          </div>
        </div>
      `
    }
  }
}

