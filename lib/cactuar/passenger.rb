# https://gist.github.com/e4337fdf7722a9e44e82
class Cactuar
  class Passenger
    def initialize(app)
      @app = app
    end

    def call(env)
      # Very dodgy hax to correct the PATH_INFO
      env["PATH_INFO"] = "/"  if env["PATH_INFO"] == ""
      r = @app.call(env)
    end
  end
end
