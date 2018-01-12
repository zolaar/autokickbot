require 'teamspeak-ruby'

# server group IDs
SG_ID = {guest: 2480686, member: 2480685, operator: 2534677, admin: 2480684}
# AFK-Time threshold for members to be kicked
AFK_TIME = 30 # AFK time in min

IP = ''
PW = ''
LOGIN = ''

$ts = ''
$sleep_time = 120 # 2 min initial value

# 'slots_available'    
def slots_available
    begin
        serverinfo = $ts.command('serverinfo')
        res_slots = serverinfo['virtualserver_reserved_slots']
        max_clients = serverinfo['virtualserver_maxclients']
        clients_online = serverinfo['virtualserver_clientsonline']
        max_clients - (res_slots + clients_online)
    rescue
        puts '[ERROR] problem getting available slots'
        raise 'slots_available'
    end
end

# 'servererror'
# 'kick'
def kick
    begin
        # getting neccessary info about clients
        clientlist_sg = $ts.command('clientlist',{},'-groups')
        clientlist_idle = $ts.command('clientlist',{},'-times')
        
        clid_idle = {} # clid => client_idle_time
        clid_nick = {} # clid => client_nickname
        clid_kickable = {} # w/o admins: clid => client_idle_time
        clid_kickable_guests = {} # only guests: clid => client_idle_time
        
        clientlist_idle.each do |user|
            clid_idle[user['clid']] = user['client_idle_time']
            clid_nick[user['clid']] = user['client_nickname']
        end
        
        clientlist_sg.each do |user|
            if user['client_servergroups'] != SG_ID[:admin]
                clid_kickable[user['clid']] = clid_idle[user['clid']]
                
                if user['client_servergroups'] == SG_ID[:guest] #if guest
                    clid_kickable_guests[user['clid']] = clid_idle[user['clid']]
                end
            end
        end
        
        # kicking client with highest idle value > 30 min
        max_idle = clid_kickable.max_by{|k,v| v}
        if max_idle[1] >= 1000*60*AFK_TIME # min -> ms
            msg = 'Server ist voll! Du warst seit ca. ' + (max_idle[1] / 1000 / 60).to_s + 'min inaktiv und wurdest deshalb gekickt.'
            $ts.command('clientkick', clid: max_idle[0], reasonid: 5, reasonmsg: msg)
            sleep 1.0
            #puts '[59] sleeping 1s ...'
            puts '[' + Time.now.to_s + '] kicking ' + clid_nick[max_idle[0]] + '.'
            puts 'Reason: Idling for ' + (max_idle[1] / 1000 / 60).to_s + 'min.'
            
            File.open('kicklog.txt', 'a'){|f|
                f.puts('[' + Time.now.to_s + '] kicking ' + clid_nick[max_idle[0]] + ' | idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min)')
            } 
            
        # kicking guests
        else
            msg = 'Server ist voll! Plätze werden für Member freigegeben. (idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min)'
            max_idle = clid_kickable_guests.max_by{|k,v| v} # kicking guest with highest idle time
            $ts.command('clientkick', clid: max_idle[0], reasonid: 5, reasonmsg: msg)
            sleep 1.0
            puts '[' + Time.now.to_s + '] kicking ' + clid_nick[max_idle[0]] + '.' 
            puts 'Reason: GUEST. (idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min)'
            
            File.open('kicklog.txt', 'a'){|f|
                f.puts('[' + Time.now.to_s + '] kicking ' + clid_nick[max_idle[0]] + ' | idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min | GUEST')
            }            
        
        end

    rescue Teamspeak::ServerError => e
        puts '[ERROR] ServerError:'
        puts e.message
        raise 'servererror'
    rescue
        raise 'kick'
    #else
    #    puts '[ERROR] something went wrong during kicking!'
    end
end

def check
    # get server information
    slots = slots_available
    sleep 1.0
    if slots < 1 #one slot should be free for member to join
        puts 'Server full! Kicking...'
        kick
    else
        puts slots.to_s+' slots available!'
    end
    
    slots = slots_available
    
    puts 'refreshing sleep time...' # sleep_time == free_slots * min
    $sleep_time = 60*(slots)
    if $sleep_time <= 60 # only 1 slot left
        $sleep_time = 30 # check every 30 s
    elsif $sleep_time >= 60*20 # only some users
        $sleep_time *= 2 # double sleep time
    end
    puts 'new sleep time: ' + $sleep_time.to_s + 's'
end

###########
# EXECUTE #
###########

## 'use'
## 'clientupdate'
## 'exit'
def run

    # INIT 
    begin
        $ts = Teamspeak::Client.new IP, 10011
        $ts.login(LOGIN, PW)
        $ts.command('use', port: 10045)
        puts 'Connection successful!'
    rescue
        puts '[ERROR] problem connecting to server!'
        raise 'use'
    end
    begin   
        bot_id = $ts.command('clientgetids', cluid: 'oszwEVqrBO1dCX89xIK95x6bHXE=')
        $ts.command('clientupdate', clid: bot_id['clid'], client_nickname: 'Igor der Adminbot')
        puts 'Clientupdate successful!'
    rescue
        puts '[ERROR] problem with \'clientgetids\' and/or clientupdate!'
        raise 'clientupdate'
    end
    puts 'INIT successful!'
    ###########
    
    loop do
        puts 'running check...'
        check
        
        #$sleep_time = 60 #debug
        puts 'next check in ' + ($sleep_time / 60.0).to_s + 'min.'
        
        #for stopping loop
        for t in 1..($sleep_time / 30)
            ready_fds = select [ $stdin ], [], [], 30
            s = ready_fds.first.first.gets unless ready_fds.nil?
            if s != nil
                #$ts.disconnect
                raise 'exit' if s.chomp == 'exit'
                raise 'inspect' if s.chomp == 'inspect'
                break if s == "\n"   
            end
            
            if t%2 == 0 # once every minute
                begin
                    $ts.command('whoami')
                    print '.'
                rescue
                    sleep 5
                    begin
                        ts.disconnect
                        ts.login(LOGIN, PW)
                        bot_id = $ts.command('clientgetids', cluid: 'oszwEVqrBO1dCX89xIK95x6bHXE=')
                        $ts.command('clientupdate', clid: bot_id['clid'], client_nickname: 'Igor der Adminbot')
                        print 'o'
                    rescue
                        print 'x'
                    end
                end
            end
        end
        puts
    end
end

errormsg = '_'
loop do
    puts '-----------'
    puts 'STARTING...'
    puts '-----------'
    
    begin
        run
    rescue RuntimeError => e
        errormsg = e.message
    end
    
    case errormsg
    when 'exit'     
        break    
    when '_'
        puts '[ERROR] No error message!'
        puts 'RESTART!'
    when 'use'
        puts '[ERROR] Server INIT failed!'
        puts 'SHUTDOWN!'
        break
    when 'clientupdate'
        puts '[ERROR] INIT failed!'
        puts 'RESTART!'
    when 'slots_available'  || 'kick'
        puts '[ERROR] RUN failed!'
        puts 'RESTART!'
    when 'servererror'
        puts '[ERROR] Server Error!'
        puts 'RESTART in 10min!'
        sleep 60*10
    when 'inspect'
        puts 'INSPECTION'
        clientlist_sg = $ts.command('clientlist',{},'-groups')
        clientlist_idle = $ts.command('clientlist',{},'-times')
        puts '---------------------------------'        
        puts 'GROUPS'
        puts '---------------------------------'
        clientlist_sg.each do |user|
            puts user.to_s
            puts
        end
        puts '---------------------------------'
        puts 'TIMES'
        puts '---------------------------------'
        clientlist_idle.each do |user|
            puts user.to_s
            puts
        end
    else
        puts '[ERROR] Something went wrong!'
        puts 'RESTART in 5min!'
        sleep 60*5
    end
    sleep 10
    begin
        $ts.disconnect
    rescue
    end
end

puts '-----------'
puts 'EXIT'
puts '-----------'   
