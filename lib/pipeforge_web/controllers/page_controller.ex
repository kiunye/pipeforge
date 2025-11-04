defmodule PipeForgeWeb.PageController do
  use PipeForgeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
