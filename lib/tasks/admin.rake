namespace :scanarr do
  namespace :admin do
    desc "Reset admin credentials: rake scanarr:admin:reset[username,password]"
    task :reset, [ :username, :password ] => :environment do |_t, args|
      username = args[:username]
      password = args[:password]

      abort "Usage: rake scanarr:admin:reset[username,password]" unless username && password
      abort "Password must be at least 8 characters" if password.length < 8

      user = User.find_by(role: :admin)
      abort "No admin user found. Run the setup wizard first." unless user

      user.update!(username: username, password: password, password_confirmation: password)
      puts "Admin credentials updated."
      puts "  Username: #{username}"
      puts "  Role: admin"
    end
  end
end
