require 'teamspeak-ruby'

begin
    $ts = Teamspeak::Client.new 'IP', PORT
    $ts.login('autokickbot', 'PASSWORD')
    $ts.command('use', port: 10045)
rescue
    puts '[ERROR] problem connecting to server!'
    puts 'SHUTDOWN'
    exit
end

bot_id = $ts.command('clientgetids', cluid: 'oszwEVqrBO1dCX89xIK95x6bHXE=')
$ts.command('clientupdate', clid: bot_id['clid'], client_nickname: 'adminbot')

$sleep_time = 120 # 2 min initial value
if $sleep_time <= 60
    $sleep_time = 30
elsif $sleep_time >= 1440
    $sleep_time = 60*60
end

# server group IDs
SG_ID = {guest: 2480686, member: 2480685, operator: 2534677, admin: 2480684}
# AFK-Time threshold for members to be kicked
AFK_TIME = 30 # AFK time in min

def kick
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
        #$ts.command('clientkick', clid: max_idle[0], reasonid: 5, reasonmsg: msg)
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
        #$ts.command('clientkick', clid: max_idle[0], reasonid: 5, reasonmsg: msg)
        puts 'kicking ' + clid_nick[max_idle[0]] + '.' 
        puts 'Reason: GUEST. (idle time: ' + (max_idle[1] / 1000 / 60).to_s + 'min)'
    end
end

def check_cap
    # get server information
    serverinfo = $ts.command('serverinfo')
    res_slots = serverinfo['virtualserver_reserved_slots']
    max_clients = serverinfo['virtualserver_maxclients']
    clients_online = serverinfo['virtualserver_clientsonline']
    slots_available = max_clients - (res_slots + clients_online)
    
    if slots_available < 1 #one slot should be free for member to join
        puts 'Server full! Kicking...'
        kick
    else
        puts slots_available.to_s+' slots available!'
    end
    
    puts 'refreshing sleep time...' # sleep_time == free_slots * min
    $sleep_time = 60*(slots_available)
    if $sleep_time <= 60
        $sleep_time = 30
    elsif $sleep_time >= 1440
        $sleep_time = 60*60
    end
    puts 'new sleep time: ' + $sleep_time.to_s + 's'
end


#######
# RUN #
#######
loop do
    check_cap
    #$sleep_time = 60 #debug
    puts 'next check in ' + ($sleep_time / 60.0).to_s + 'min.'
    
    #for stopping loop
    ready_fds = select [ $stdin ], [], [], $sleep_time
    s = ready_fds.first.first.gets unless ready_fds.nil?
    if s != nil
        break if s.chomp == 'exit' 
    end
    puts 'continue...'
end

$ts.disconnect
