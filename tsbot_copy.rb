require 'teamspeak-ruby'

# server group IDs
SG_ID = {guest: 2480686, member: 2480685, operator: 2534677, admin: 2480684}
# AFK-Time threshold for members to be kicked
AFK_TIME = 30 # AFK time in min

IP = ''
PW = ''

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
        clientlist = $ts.command('clientlist')
        clid_sg = {}
        clid_idle = {}
        clid_nick = {}
        clientlist.each do |user|
            # client ID => server group 
            clid_sg[user['clid']] = $ts.command('clientinfo', clid: user['clid'])['client_servergroups'] 
            sleep 0.5 # avoid flood ban 
            if clid_sg[user['clid']] != SG_ID[:admin] # no kick for admins
                # client ID => idle time
                clid_idle[user['clid']] = $ts.command('clientinfo', clid: user['clid'])['client_idle_time']
            end
            clid_nick[user['clid']] = user['client_nickname']
            sleep 0.5 # avoid flood ban 
        end
        
        # kicking client with highest idle value > 30 min
        max_idle = clid_idle.max_by{|k,v| v}
        if max_idle[1] >= 1000*60*AFK_TIME # min -> ms
            msg = 'Server ist voll! Du warst seit ca. ' + (max_idle[1] / 1000 / 60).to_s + 'min inaktiv und wurdest deshalb gekickt.'
            $ts.command('clientkick', clid: max_idle[0], reasonid: 5, reasonmsg: msg)
            puts 'kicking ' + clid_nick[max_idle[0]] + '.'
            puts 'Reason: Idling for ' + (max_idle[1] / 1000 / 60).to_s + 'min.'
            
        # kicking guests
        else
            clid_idle_guest = {}
            clientlist.each do |user|
                if clid_sg[user['clid']] == SG_ID[:guest] # if guest
                    clid_idle_guest[user['clid']] = $ts.command('clientinfo', clid: user['clid'])['client_idle_time']
                end
                sleep 0.5
            end
            msg = 'Server ist voll! Plätze werden für Member freigegeben. (idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min)'
            max_idle = clid_idle_guest.max_by{|k,v| v} # kicking guest with highest idle time
            $ts.command('clientkick', clid: max_idle[0], reasonid: 5, reasonmsg: msg)
            puts 'kicking ' + clid_nick[max_idle[0]] + '.' 
            puts 'Reason: GUEST. (idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min)'
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
    
    if slots < 1 #one slot should be free for member to join
        puts 'Server full! Kicking...'
        kick
    else
        puts slots.to_s+' slots available!'
    end
    
    slots = slots_available
    
    puts 'refreshing sleep time...' # sleep_time == free_slots * min
    $sleep_time = 60*(slots)
    if $sleep_time <= 60
        $sleep_time = 30
    elsif $sleep_time >= 1440
        $sleep_time = 60*60
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
        $ts.login('autokickbot', PW)
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
        for t in 1..$sleep_time
            ready_fds = select [ $stdin ], [], [], 60
            s = ready_fds.first.first.gets unless ready_fds.nil?
            if s != nil
                #$ts.disconnect
                raise 'exit' if s.chomp == 'exit'
            end
            
            begin
                $ts.command('whoami')
                puts 'still alive...'
            rescue
                puts 'dead'
            end
        end
        puts ''
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
    else
        puts '[ERROR] Something went wrong!'
        puts 'RESTART in 5min!'
        sleep 60*5
    end
    sleep 60
    begin
        $ts.disconnect
    rescue
    end
end

puts '-----------'
puts 'EXIT'
puts '-----------'   

# serverinfo = $ts.command('serverinfo')
# res_slots = serverinfo['virtualserver_reserved_slots']
# max_clients = serverinfo['virtualserver_maxclients']
# clients_online = serverinfo['virtualserver_clientsonline']
# slots_available = max_clients - (res_slots + clients_online)


# puts 'clientlist'
# $ts.command('clientlist').each do |user|
  # puts user #$ts.command('clientinfo', clid: user['clid'])['client_idle_time']
  # print '===== '
  # puts $ts.command('clientinfo', clid: user['clid'])
  # sleep 2
# end

# puts '#####################################'

# $ts.command('clientlist').each do |user|
  # puts user #$ts.command('clientinfo', clid: user['clid'])['client_idle_time']
  # print '===== '
  # puts $ts.command('clientinfo', clid: user['clid'])['client_servergroups']
  # sleep 2
# end

# #####################################
# {"clid"=>4, "cid"=>8183626, "client_database_id"=>34663189, "client_nickname"=>"
# Happens", "client_type"=>0}
# ===== 2480686 -> Guest
# {"clid"=>5, "cid"=>8160605, "client_database_id"=>29232480, "client_nickname"=>"
# Thunaer", "client_type"=>0}
# ===== 2480684 -> Admin
# {"clid"=>8, "cid"=>8183635, "client_database_id"=>30772024, "client_nickname"=>"
# zolar", "client_type"=>0}
# ===== 2480684,2534677 -> Admin, Operator
# {"clid"=>13, "cid"=>9088092, "client_database_id"=>31019769, "client_nickname"=>
# "aaron", "client_type"=>0, "error"=>nil, "id"=>0, "msg"=>"ok"}
# ===== 2480685 -> Member
# ----------------------


#puts ts.command('clientlist')

#{"clid"=>27, "cid"=>8160605, "client_database_id"=>30772024, "client_nickname"=>"zolar", "client_type"=>0}


#sleep(10000)

#TEST
# ts.command('clientlist').each do |user|
    # if user['client_nickname'] == 'zolar'
        # ts.command('clientpoke', clid: user['clid'], msg: 'TESTPOKE')
    # end
# end

# puts ts.command('hostinfo')['host_timestamp_utc']