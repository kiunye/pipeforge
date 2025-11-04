export const DownloadCSV = {
  mounted() {
    this.handleEvent("download_csv", ({content, filename}) => {
      const blob = new Blob([content], { type: "text/csv" })
      const url = window.URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = filename
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      window.URL.revokeObjectURL(url)
    })
  }
}

