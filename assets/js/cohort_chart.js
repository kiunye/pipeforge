import { Chart } from "chart.js/auto"

export const CohortChart = {
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

    // Transform cohort data for Chart.js
    // Group by cohort_month and create datasets
    const cohortGroups = {}
    
    data.forEach(item => {
      const cohortKey = item.cohort_month || "Unknown"
      if (!cohortGroups[cohortKey]) {
        cohortGroups[cohortKey] = []
      }
      cohortGroups[cohortKey].push({
        period: item.period_index,
        retention: item.retention_rate * 100 // Convert to percentage
      })
    })

    // Create datasets for each cohort
    const datasets = Object.entries(cohortGroups).map(([cohortMonth, periods], index) => {
      const hue = (index * 137.508) % 360 // Golden angle for color distribution
      const color = `hsl(${hue}, 70%, 50%)`
      
      // Sort periods by period_index and fill gaps
      const sortedPeriods = periods.sort((a, b) => a.period - b.period)
      const maxPeriod = Math.max(...sortedPeriods.map(p => p.period))
      const retentionByPeriod = {}
      
      sortedPeriods.forEach(p => {
        retentionByPeriod[p.period] = p.retention
      })

      // Fill array for all periods
      const retentionData = []
      for (let i = 0; i <= maxPeriod; i++) {
        retentionData.push(retentionByPeriod[i] || null)
      }

      return {
        label: formatCohortLabel(cohortMonth),
        data: retentionData,
        borderColor: color,
        backgroundColor: color.replace("50%)", "20%)"),
        tension: 0.4,
        fill: false
      }
    })

    // Generate period labels
    const maxPeriod = Math.max(...Object.values(cohortGroups).flat().map(p => p.period))
    const labels = Array.from({ length: maxPeriod + 1 }, (_, i) => `Month ${i}`)

    // Use Chart.js to render chart
    try {
      const ctx = canvas.getContext("2d")
      this.chart = new Chart(ctx, {
        type: "line",
        data: {
          labels: labels,
          datasets: datasets
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              display: datasets.length <= 5,
              position: "bottom"
            },
            tooltip: {
              callbacks: {
                label: function(context) {
                  const value = context.parsed.y
                  return value !== null ? `${value.toFixed(1)}%` : "N/A"
                }
              }
            }
          },
          scales: {
            y: {
              beginAtZero: true,
              max: 100,
              ticks: {
                callback: function(value) {
                  return value + "%"
                }
              },
              title: {
                display: true,
                text: "Retention Rate (%)"
              }
            },
            x: {
              title: {
                display: true,
                text: "Period (Months)"
              }
            }
          }
        }
      })
    } catch (error) {
      // Fallback: render simple text representation
      console.error("Cohort chart error:", error)
      canvas.parentElement.innerHTML = `
        <div class="p-4">
          <p class="text-sm text-gray-500 mb-2">Chart rendering failed. Showing data as list.</p>
          <div class="space-y-1 text-xs">
            ${Object.entries(cohortGroups).map(([cohort, periods]) => `
              <div class="mb-2">
                <strong>${formatCohortLabel(cohort)}:</strong>
                ${periods.map(p => `Period ${p.period}: ${p.retention.toFixed(1)}%`).join(", ")}
              </div>
            `).join("")}
          </div>
        </div>
      `
    }
  }
}

function formatCohortLabel(cohortMonth) {
  if (!cohortMonth) return "Unknown"
  
  try {
    const date = new Date(cohortMonth)
    return date.toLocaleDateString("en-US", { year: "numeric", month: "short" })
  } catch {
    return cohortMonth.toString()
  }
}


