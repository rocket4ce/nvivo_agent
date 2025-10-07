defmodule NvivoAgentWeb.PageController do
  use NvivoAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
