README.md                                                                                           0000644 0000000 0000000 00000001001 12736247662 011042  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   forked by Ronsor
An implementation of (parts of) the irc server protocol written in C. Currently in the process of debugging to the point that it works and supports basic join/privmsg messages.

## Features implemented:

1. Connection registration commands
2. Client data structure and functions
3. Channel data structure and functions
4. Main loop(select() based)
5. Sending/receiving correctly formatted IRC messages over the network
6. Join/part channels
7. Quit command
8. Privmsg command
9. Welcome messages
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               channel.c                                                                                           0000644 0000000 0000000 00000012416 12735556134 011347  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "command.h"
#include "network_io.h"
#include "channel.h"
#include "channel_stat.h"
#include "client.h"
#include "replies.h"

struct channel channels[MAX_CHANNELS];

static int n_channels = 0;

int in_channel(struct channel *chan, int cli_fd)
{
	int i;

	for (i = 0; i < MAX_JOIN; i++) {
		if ((chan->joined_users[i] != NULL) && (chan->joined_users[i]->fd == cli_fd))
			return 1;
	}

	return 0;
}

struct channel *get_channel(char *chan_name)
{
	int i;

	for (i = 0; i < MAX_CHANNELS; i++)
		if (strncmp(channels[i].name, chan_name, 20) == 0)
			break;

	if (i == MAX_CHANNELS)
		return NULL;
	
	return &(channels[i]);
}

struct channel *new_channel(char *chan_name)
{
	int i;

	for (i = 0; i < MAX_CHANNELS; i++) {
		if (channels[i].n_joined == -1) /* -1 users joined means this slot in the channel array is open */
			break;
	}

	if (i == MAX_CHANNELS)
		return NULL;

	strncpy(channels[i].name, chan_name, 20);
	channels[i].n_joined = 0;

	n_channels++;

	return &(channels[i]);
}

static void remove_inactive_channels(int n)
{
	int n_removed = 0;
	int i;

	for (i = 0; i < MAX_CHANNELS; i++) {
		if (n_removed == n)
			break;
		if (channels[i].n_joined == 0) {
			memset(&channels[i], 0x00, sizeof(struct channel));
			channels[i].n_joined = 1;
			n_removed++;
		}
	}
}

static void join_channel(struct channel *chan, struct client *cli)
{
	int i, j;

	if (cli->n_joined == MAX_CHAN_JOIN) {
	        send_message(cli->fd, -1, "%d %s %s :You have joined too many channels", ERR_TOOMANYCHANNELS, cli->nick, chan->name);
       		return;
	}	

	for (i = 0; i < MAX_JOIN; i++) {
		if (chan->joined_users[i] == NULL) {
			chan->joined_users[i] = cli;
			chan->n_joined++;	

			/* add to clients joined channel list */
			for (j = 0; j < MAX_CHAN_JOIN; j++) {
				if (cli->joined_channels[j] == NULL) {
					cli->joined_channels[j] = chan;
					cli->n_joined++;
					break;
				}
			}

			break;
		}
	}

	if (i == MAX_JOIN) {
		send_message(cli->fd, -1, "%d %s %s :Cannot join channel (+l)", ERR_CHANNELISFULL, cli->nick, chan->name);
		return;
	}

	send_channel_greeting(chan, cli);
}

void part_user(struct channel *chan, struct client *cli)
{
	int i;

	/* find the spot in the joined users array where the client is */
	for (i = 0; i < MAX_JOIN; i++) {
		if((chan->joined_users[i] != NULL) && (cli->fd == chan->joined_users[i]->fd))
			break;
	}

	if (i == MAX_JOIN) {
		send_message(cli->fd, -1, "%d %s %s :You are not on that channel", ERR_NOTONCHANNEL, cli->nick, chan->name);
		return;	
	}

	chan->joined_users[i] = NULL;
	chan->n_joined--;

	/* remove channel from the client 
	list of joined_channels */
	for (i = 0; i < MAX_CHAN_JOIN; i++) {
		if (strcmp(cli->joined_channels[i]->name, chan->name) == 0) {
			cli->joined_channels[i] = NULL;
			cli->n_joined--;
			break;
		}
	}
}

static void handle_join(int fd, int argc, char **args)
{
	struct client *cli = get_client(fd);
	struct channel *chan;
	
	if (argc < 2) {
		send_message(fd, -1, "%d %s %s :Not enough parameters", ERR_NEEDMOREPARAMS, cli->nick, args[0]);
		return;
	}

	char *bufp = args[1];
	int i, n = 1;

	while (*bufp != '\0') { /* could be multiple channels passed to one command, they should be comma-separated */
		if (*bufp == ',') {
			*bufp = '\0';
			n++;
		}
	
		bufp++;
	}

	bufp = args[1];
	for (i = 0; i < n; i++) {
		if ((chan = get_channel(bufp)) == NULL) {
			if ((chan = new_channel(bufp)) == NULL) {
				send_message(fd, -1, "%d %s %s :No such channel/Too many channels", ERR_NOSUCHCHANNEL, cli->nick, args[0]);
				return;
			}
		}
		
		if (in_channel(chan, cli->fd)) /* can't join a channel twice, but IRC specifies no error code for this */
			continue;

		/* Must be in this order */
		send_message(cli->fd, cli->fd, "JOIN %s", bufp);
		join_channel(chan, cli);
		send_to_channel(chan, cli->fd, "JOIN %s", bufp);

		/* advance to next channel name */
		while (*bufp != '\0') bufp++;
		bufp++;
	}
}
static void channel_list(int fd, int argc, char **args){
	int i;
	struct client* cli = get_client(fd);
	for (i = 0; i < MAX_CHANNELS; i++ ) {
		if(channels[i].name[0] != '\0') {
			send_message(fd, -1, "%d %s %s %d :%s", RPL_LIST, cli->nick,
			channels[i].name, channels[i].n_joined, 
			channels[i].topic);
		}
	}
}
static void handle_part(int fd, int argc, char **args)
{
	struct client *cli = get_client(fd);
	struct channel *chan;

	if (argc < 2) {
		send_message(fd, -1, "%d %s %s :Not enough parameters", ERR_NEEDMOREPARAMS, cli->nick, args[0]);
		return;
	}

	char *bufp = args[1];
	int i, n = 1;

	while (*bufp != '\0') {
		if (*bufp == ',') {
			n++;
			*bufp = '\0';
		}

		bufp++;
	}

	bufp = args[1];

	for (i = 0; i < n; i++) {
		if ((chan = get_channel(bufp)) == NULL) {
			send_message(fd, -1, "%d %s %s :No such channel", ERR_NOSUCHCHANNEL, cli->nick, args[0]);
			return;
		}

		send_message(cli->fd, cli->fd, "PART %s %s", bufp, args[2]);
		part_user(chan, cli);
		send_to_channel(chan, cli->fd, "PART %s %s", chan->name, args[2]);

		/* advance to next channel name */
		while (*bufp != '\0') bufp++;
		bufp++;
	}
}

void initialize_channels()
{
	int i;

	memset(&channels, 0x00, sizeof(struct channel) * MAX_CHANNELS);

	for (i = 0; i < MAX_CHANNELS; i++)
		channels[i].n_joined = -1;

	register_command("JOIN", handle_join);
	register_command("PART", handle_part);
	register_command("LIST", channel_list);
}
                                                                                                                                                                                                                                                  channel.h                                                                                           0000644 0000000 0000000 00000001074 12734521747 011353  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef CHANNEL_H
#define CHANNEL_H

#define MAX_CHANNELS 40
#define MAX_JOIN 20

struct channel {
	char name[20];
	struct client *joined_users[MAX_JOIN];
	int n_joined; 
	unsigned int mode; /*bit mask representing private/secret/invite-only/topic/moderated/ */

	char topic[400];
	char topic_setter[20];
	time_t topic_set_time;
};

void initialize_channels();

struct channel *new_channel(char *chan_name);
struct channel *get_channel(char *chan_name);

int in_channel(struct channel *chan, int cli_fd);

void part_user(struct channel *chan, struct client *cli);

#endif
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    channel_stat.c                                                                                      0000644 0000000 0000000 00000005020 12734521747 012374  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <string.h>
#include <time.h>

#include "channel_stat.h"
#include "channel.h"
#include "command.h"
#include "network_io.h"
#include "replies.h"

static void handle_topic(int fd, int argc, char **args)
{
	struct channel *chan;
	struct client *cli = get_client(fd);

	if (argc < 3) { /* Show topic */
		if (argc < 2) {
			send_message(fd, -1, "%d %s %s :Not enough parameters", ERR_NEEDMOREPARAMS, cli->nick, args[0]);
			return;
		}
	
		chan = get_channel(args[1]);

		if (!in_channel(chan, fd)) {
			send_message(fd, -1, "%d %s %s :You are not on that channel", ERR_NOTONCHANNEL, cli->nick, args[1]);
			return;

		}

		if (chan->topic_set_time == 0) {
			send_message(fd, -1, "%d %s %s :Topic not set", RPL_NOTOPIC, cli->nick, args[1]);
			return;
		}

		send_message(fd, -1, "%d %s %s %s", RPL_TOPIC, cli->nick, args[1], chan->topic);
		send_message(fd, -1, "%d %s %s %s %d", RPL_TOPICWHOTIME, cli->nick, args[1], chan->topic_setter, chan->topic_set_time);
		return;
	}

	chan = get_channel(args[1]);

	/* View topic */
	send_message(cli->fd, cli->fd, "TOPIC %s %s", args[1], args[2]);
	send_to_channel(chan, cli->fd, "TOPIC %s %s", args[1], args[2]);

	if (strlen(args[2]) > 1) { /* one character for ':' */
		chan->topic_set_time = time(NULL);
		strncpy(chan->topic_setter, cli->nick, 20);
		strncpy(chan->topic, args[2], 400);
	} else { /* unset topic */
		chan->topic_set_time = 0;
	}
}

void send_channel_greeting(struct channel *chan, struct client *cli)
{
	char user_list[400];
	
	int i, n = 0;

	if (chan->topic_set_time != 0) {
		send_message(cli->fd, -1, "%d %s %s %s", RPL_TOPIC, cli->nick, chan->name, chan->topic);	
		send_message(cli->fd, -1, "%d %s %s %s %d", RPL_TOPICWHOTIME, cli->nick, chan->name, chan->topic_setter, chan->topic_set_time);
	}

	memset(user_list, 0x00, 400);

	for (i = 0; i < MAX_JOIN; i++) {
		if (chan->joined_users[i] != NULL) {
			strncat(user_list, chan->joined_users[i]->nick, 20);
			strncat(user_list, " ", 1);
			n += strlen(chan->joined_users[i]->nick + 1);
			
			if (n >= 379) { /* if maximum capacity reached, send what we have so far */
				send_message(cli->fd, -1, "%d %s = %s :%s", RPL_NAMREPLY, cli->nick, chan->name, user_list);
				memset(user_list, 0x00, 400);
				n = 0;
			}
		}
	}

	if (n > 0) {
		send_message(cli->fd, -1, "%d %s = %s :%s", RPL_NAMREPLY, cli->nick, chan->name, user_list);
		memset(user_list, 0x00, 400);
	}

	send_message(cli->fd, -1, "%d %s %s :End of /NAMES list", RPL_ENDOFNAMES, cli->nick, chan->name);
}

void initialize_channel_stat()
{
	register_command("TOPIC", handle_topic);
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                channel_stat.h                                                                                      0000644 0000000 0000000 00000000262 12734521747 012404  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef CHANNEL_STAT_H
#define CHANNEL_STAT_H

#include "channel.h"

void send_channel_greeting(struct channel *chan, struct client *cli);
void initialize_channel_stat();
#endif
                                                                                                                                                                                                                                                                                                                                              client.c                                                                                            0000644 0000000 0000000 00000011315 12735767655 011226  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include "command.h"
#include "global_stat.h"
#include "client.h"
#include "replies.h"
#include "network_io.h"
#include "channel.h"
//#include "global.h"
extern int hostcloak;
#define NICK_REGISTERED 2
#define USER_REGISTERED 1

struct client clients[MAX_CLIENTS];
int n_clients = 0;

int new_client(int cli_fd)
{
	int i;
	struct sockaddr_in cliaddr;
	unsigned sockaddr_len = sizeof(struct sockaddr_in);

	if (n_clients == MAX_CLIENTS) {
		printf("Error: Max number of clients reached.\n");
		return -1;
	}

	for (i = 0; i < MAX_CLIENTS; i++) 
		if (clients[i].fd == -1)
			break;

	clients[i].fd = cli_fd;
	if (getpeername(cli_fd, (struct sockaddr *) &cliaddr, &sockaddr_len) < 0) {
		perror("getpeername");
		return -1;
	}
	if ( hostcloak == 0 ) {
	inet_ntop(AF_INET, &(cliaddr.sin_addr), clients[i].ip_addr, 20); 
	} else {
	memset(clients[i].ip_addr, 0, 30);
	strncpy(clients[i].ip_addr, crypt(inet_ntoa(cliaddr.sin_addr), "asigd"), 25);
	}
	clients[i].registered = 0;

	n_clients++;
	return 0;
}

int remove_client(int cli_fd)
{
	int i;
	struct client *cli = get_client(cli_fd);

	for (i = 0; i < MAX_CHAN_JOIN; i++) {
		if (cli->joined_channels[i] != NULL)
			part_user(cli->joined_channels[i], cli);
	}

	memset(cli, 0x00, sizeof(struct client));
	cli->fd = -1;

	return 0;
}

/* get client by file descriptor */
struct client *get_client(int cli_fd)
{
	int i;

	for (i = 0; i < MAX_CLIENTS; i++)
	        if (clients[i].fd == cli_fd)
	       		return &clients[i];

	return NULL;
}

/* get client by nick name */
struct client *get_client_nick(char *nick)
{
	int i;

	for (i = 0; i < MAX_CLIENTS; i++) {
		if (strncmp(clients[i].nick, nick, 20) == 0)
			return &clients[i];
	}

	return NULL;
}

/* get properly formatted prefix of client(sender) information */
int get_client_prefix(int cli_fd, char *sender_buffer)
{
	int i;

	for (i = 0; i < MAX_CLIENTS; i++) {
		if (clients[i].fd == cli_fd)
			break;
	}

	if (i == MAX_CLIENTS) {
		printf("Error: No client for file descriptor %d was found.\n", cli_fd);
		return -1;
	}
	
	snprintf(sender_buffer, 256, "%s!%s@%s", clients[i].nick, clients[i].user, clients[i].ip_addr);
	return 0;
}

static int is_erroneus(char *nick)
{
	int i;

	if (isdigit(nick[0]))
		return 1;

	char allowed[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-\\[]{}^|";

	for (i = 0; nick[i] != '\0'; i++) {
		if (!strchr(allowed, nick[i]))
			return 1;
	}

	return 0;
}

static void set_nick(int fd, int argc, char **args)
{
	int i;
	struct client *cli = get_client(fd);

	if (argc < 2) {
		send_message(fd, -1, "%d :No nickname was given", ERR_NONICKNAMEGIVEN);
		return;
	}

	for (i = 0; i < MAX_CLIENTS; i++) {
		if (clients[i].nick[0] && (strncmp(args[1], clients[i].nick, 20) == 0)) {
			send_message(fd, -1, "%d %s :Nickname is already in use", ERR_NICKNAMEINUSE, args[1]);
			return;
		}
	}

	if (is_erroneus(args[1])) {
		send_message(fd, -1, "%d %s :Erroneous nickname", ERR_ERRONEUSNICKNAME, args[1]);
		return;
	}
	
	cli->registered |= NICK_REGISTERED;

	if (cli->welcomed) 
		send_to_all_visible(cli, "NICK %s", args[1]);

	strncpy(cli->nick, args[1], 20);
	
	/* if nick and user are both set, then mark this client as registered */
	if (cli->registered == 3 && !cli->welcomed) {
		send_welcome(cli);
		cli->welcomed = 1;
	}
}

static void set_user(int fd, int argc, char **args)
{
	struct client *cli = get_client(fd);

	if (argc < 5) {
		send_message(fd, -1, "%d %s :Not enough parameters", ERR_NEEDMOREPARAMS, args[0]); 
		return;
	}

	if (cli->registered & USER_REGISTERED) {
		send_message(fd, -1, "%d :Unauthorized command (already registered)", 
		ERR_ALREADYREGISTERED);
		return;
	}

	cli->registered |= USER_REGISTERED;
	
	strncpy(cli->user, args[1], 20);
	
	strncpy(cli->realname, args[4], 30);
	cli->mode |= atoi(args[2]);

	/* if nick and user are both set, then mark this client as registered. 3 = both bits set */
	if (cli->registered == 3 && !cli->welcomed) {
		send_welcome(cli);
		cli->welcomed = 1;
	}
}
static void whois(int fd, int argc, char **argv){
	if(argc == 1) return;
	struct client* clt = get_client_nick(argv[1]);
	struct client* cli = get_client(fd);
	if ( clt == NULL ) return;
	send_message(fd, -1, "%d %s %s %s %s * :%s", RPL_WHOISUSER, cli->nick, clt->nick, 
	clt->user, 
	clt->ip_addr, clt->realname);
	send_message(fd, -1, "%d %s %s :End of /WHOIS Reply", RPL_ENDOFWHOIS, cli->nick, 
	clt->nick);
}
void initialize_clients()
{
	int i;

	memset(clients, 0x00, sizeof(struct client) * MAX_CLIENTS);

	for (i = 0; i < MAX_CLIENTS; i++)
		clients[i].fd = -1;

	register_command("USER", set_user);
	register_command("NICK", set_nick);
	register_command("WHOIS", whois);
}

                                                                                                                                                                                                                                                                                                                   client.h                                                                                            0000644 0000000 0000000 00000001212 12735766247 011222  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef CLIENT_H
#define CLIENT_H

#include <sys/socket.h>
#include <netinet/in.h>
#include <time.h>

#define MAX_CLIENTS 896
#define MAX_CHAN_JOIN 96

struct client {
	time_t last_activity;

	char user[20];
	char nick[20];
	char realname[30];
	char ip_addr[50];

	struct channel *joined_channels[MAX_CHAN_JOIN];
	int n_joined;
	
	int mode;
	int fd;
	
	int registered;
	int welcomed;
};

extern int n_clients;

void initialize_clients();

int new_client(int conn_fd);
int remove_client(int conn_fd);

struct client *get_client(int conn_fd);
struct client *get_client_nick(char *nick);

int get_client_prefix(int cli_fd, char *sender_buffer);

#endif
                                                                                                                                                                                                                                                                                                                                                                                      command.c                                                                                           0000644 0000000 0000000 00000002101 12735561522 011340  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <arpa/inet.h>

#include "network_io.h"
#include "client.h"
#include "channel.h"
#include "replies.h"
#include "command.h"

#define MAX_COMMANDS 25

struct command {
	char cmd[10];
	void (*cmd_cb)(int fd, int argc, char **args);
};

static struct command commands[MAX_COMMANDS]; 
static int n_commands = 0;

void register_command(char *cmd_name, void (*callback)(int fd, int argc, char **args))
{
	int i;

	for (i = 0; i < n_commands; i++) {
		if (strncmp(commands[i].cmd, cmd_name, 10) == 0)
			break;
	}

	if (i == n_commands) { /* adding a new command */
		strncpy(commands[i].cmd, cmd_name, 10);
		n_commands++;
	}

	commands[i].cmd_cb = callback;
}

void handle_command(int fd, int argc, char **args)
{
	int i;
	
	struct client *cli = get_client(fd);

	for (i = 0; i < n_commands; i++) {
		if (strcmp(args[0], commands[i].cmd) == 0) {
			commands[i].cmd_cb(fd, argc, args);
			break;
		}
	}

//	if (i == n_commands)
//		send_message(fd, -1, "%d %s %s :Unknown command", ERR_UNKNOWNCOMMAND, 
//cli->nick, args[0]);
}	
                                                                                                                                                                                                                                                                                                                                                                                                                                                               command.h                                                                                           0000644 0000000 0000000 00000000271 12734521747 011357  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef COMMAND_H
#define COMMAND_H

void register_command(char *cmd_name, void (*callback)(int fd, int argc, char **args));
void handle_command(int fd, int argc, char **args);

#endif
                                                                                                                                                                                                                                                                                                                                       global.c                                                                                            0000644 0000000 0000000 00000003607 12734521747 011202  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <arpa/inet.h>

#include "command.h"
#include "client.h"
#include "global.h"
#include "network_io.h"
#include "replies.h"

static void handle_ping(int fd, int argc, char **args)
{
	char addr_buffer[30];

	struct sockaddr_in server_addr;
	socklen_t addrlen = sizeof(struct sockaddr);

	getsockname(fd, (struct sockaddr *) &server_addr, &addrlen);

	inet_ntop(AF_INET, &(server_addr.sin_addr), addr_buffer, 30);

	send_message(fd, -1, "PONG %s", addr_buffer); 	
}

static void handle_privmsg(int fd, int argc, char **args)
{
	struct client  *cli = get_client(fd);
	struct channel *target_chan;
	struct client *target_cli;

	char *bufp = args[1];
	int i, n = 1;
	int is_channel = 1;

	if (argc < 3) {
		send_message(fd, -1, "%d %s :No text to send", ERR_NOTEXTTOSEND, cli->nick);
		return;
	}

	if (argc < 2) {
		send_message(fd, -1, "%d %s :No recipient given (PRIVMSG)", ERR_NORECIPIENT, cli->nick);
		return;
	}

	while (*bufp != '\0') {
		if (*bufp == ',') {
			n++;
			*bufp = '\0';
		}
		
		bufp++;
	}

	bufp = args[1];

	for (i = 0; i < n; i++) {
		if ((target_chan = get_channel(bufp)) == NULL) {
			if ((target_cli = get_client_nick(bufp)) == NULL) {
				send_message(fd, -1, "%d %s %s :No such nick/channel", ERR_NOSUCHNICK, cli->nick, bufp);
				continue;
			}

			is_channel = 0;
		}

		if (is_channel && !in_channel(target_chan, cli->fd)) {
			send_message(fd, -1, "%d %s %s :Cannot send to channel", ERR_CANNOTSENDTOCHAN, cli->nick, bufp);
			continue;
		}

		is_channel ? send_to_channel(target_chan, cli->fd, "PRIVMSG %s %s", bufp, args[2]) : send_message(target_cli->fd, cli->fd, "PRIVMSG %s %s", bufp, args[2]);
	}
}

void user_quit(int cli_fd, char *quit_message)
{
	struct client *cli = get_client(cli_fd);
	send_to_all_visible(cli, "QUIT %s", quit_message);
	remove_client(cli_fd);
}

void initialize_global()
{
	register_command("PING", handle_ping);
	register_command("PRIVMSG", handle_privmsg);
}

                                                                                                                         global.h                                                                                            0000644 0000000 0000000 00000000401 12735764210 011167  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef SERVER_H
#define SERVER_H

void initialize_global();
void user_quit(int cli_fd, char *quit_message);
#ifndef __MAIN
extern int gport;
extern char gservname[64];
extern int hostcloak;
#else
int gport;
int hostcloak;
char gservname[64];
#endif
#endif
                                                                                                                                                                                                                                                               global_stat.c                                                                                       0000644 0000000 0000000 00000002224 12735557510 012225  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <time.h>
#include <arpa/inet.h>

#include "replies.h"
#include "global_stat.h"
#include "network_io.h"

const char *server_version = __DATE__;
char motd[1024];

time_t server_start_time;

void initialize_global_stat()
{
	server_start_time = time(NULL);
}	

void send_welcome(struct client *cli)
{
	char addr_buffer[30];

	struct sockaddr_in server_addr;
	socklen_t addrlen = sizeof(struct sockaddr);

	getsockname(cli->fd, (struct sockaddr *) &server_addr, &addrlen);

	inet_ntop(AF_INET, &(server_addr.sin_addr), addr_buffer, 30);

	send_message(cli->fd, -1, "%03d %s :Welcome to the %s!%s@%s", RPL_WELCOME, cli->nick, cli->nick, cli->user, cli->ip_addr);
	send_message(cli->fd, -1, "%03d %s :Your host is %s, running version %s", RPL_YOURHOST, cli->nick, addr_buffer, server_version); 
	send_message(cli->fd, -1, "%03d %s :This server was created %s", RPL_CREATED, cli->nick, ctime(&server_start_time));
	send_message(cli->fd, -1, "%d %s :-%s Message of the day-", RPL_MOTDSTART, cli->nick, addr_buffer);
	send_message(cli->fd, -1, "%d %s :-%s", RPL_MOTD, cli->nick, motd);
	send_message(cli->fd, -1, "%d %s :End of /MOTD command", RPL_ENDOFMOTD, cli->nick);
}
                                                                                                                                                                                                                                                                                                                                                                            global_stat.h                                                                                       0000644 0000000 0000000 00000000337 12735557554 012245  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef STAT_H
#define STAT_H

#include "client.h"

extern char motd[1024];
extern const char *server_version;
extern time_t server_start_time;

void initialize_global_stat();

void send_welcome(struct client *cli);
#endif
                                                                                                                                                                                                                                                                                                 ircd                                                                                                0000755 0000000 0000000 00000026544 12735771013 010444  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF                �   4       4    (                   *(  *(           �@ K�@ K�@              �C� UPX!	��      R  R     �   7�$�ELF  @mw�=4N,	  l��(  @  �k�AB�7�`  ph�3w(  #�{ @ Eh7;s_Dug�[�ؗ@?���[ �_dt� ��Q         �  DT  N   ���/libd-uCc.so.0 �  ��D��  *i�Y�o @0?wi.� 
��/e�tM
�Opi���E]�k��/s��6�pWΓg�
p7^pp�w�k CGF���WW�J2X�4BgN�N�#�";���*��w�A��K 	��i�fTE=
���5->LR݀���; <%� � UO+4�48#3H��P).6`\!1�4M�Q6'$7H�t/W2$M:&@� M�H(4G�4M79AY?	�,0�2`I�X7S4�`M7I]D�l3�V[  W t��Z z���#�T�$���=������`�s� Is�K�/�GX|�!�S�d�n����@/�'M]/��T��������7�Xr;�d/>��Nɏ</ 9�uG�/��'MwX��,����� �����o�����,lZ��(�4��r�}���OO?_���l�{��Sw�������_$�����e��m�1���)O_�%�w�4�g/.:��x��\n�W�S �ۦ�4|���^_��n��q�`T�/|A�I����
�?p,�t��Z��o�_`�܀�? ��f@� ��	�0o X0�H��&gO0��0� ����?���4O���=�\*� M7`_�м�-͜�O����m�?��ߗA�n�/���8�=�58��/<�in�?�&$�i�$M�\_����x�X 7����H�i��%��4��4�`@:�y$Pu�@^�<iH d�C���/L�9�����O@�t��/?B--IwX/��0?�lI� �o�>3������lI.<�j���?��u������/���_/��=$�/����D!8��/ȭOL/�Y`0e9��#�Y���$_����_deregist_frame_infoB�>�Jv_R�n��asse�itf��r5�_ma 5ma{�� Hcomnߵvkmg&en��n�,Esatrcmpm���ncpy.h8ٶ]�nelkaru5r9-ٖ�tow{���d
&_g�{־�KgZlaatw����_�ck�cty��ƶp�b hsalKv��Zk��Dw\ܽA�5Doi nsPvk��>�n?�roB�so�hoKoak�n%oT�}�p	a cro�	�b� 6�move.�6gxrvH|o��vh��i"W��-2td��pfpu�ֶ͉.gNlm�fs��Vh��fp�l>޷��jf� zej;4�Ƅo�bi�l�;۶�C�iIiz�g.bS�K��t�0�!��� >�[e���p��Wcctv�	�	�ad��c�'�qu�m��LFs`a3kfC�q0�P����Bn�&a?wri��h��p.ȱwko�vsn	�tfg%��"t�b��_DYNAM����IC_LINKG[RLD_MAP	GL����OBAL_OFFSET_TABLE_>:ж�mfMx0d�a����
eh�9�&���Y�<'�����!'����������4��˓#l���� Ȟ{�9| �	�3/w$/d<< �g��V,u�{w7�d� ؋ �����J�����'�"GpK@��� ��E�\���ɌYU	$B�{�??�= ������&^� O$h��}�߬�;$�Ed7�3M�{�����(6�K�D��K�n텟c�\\Kg�-%|$�Gt+#`����Ex�/x�3$�	�o /?;/�n!���[��ps�!؏���K$����h���$����L����3�����a_[V�O��������!$,F�/S�!�G<��FnmccEB���7f��!��װ�%/�Ϩ�v[�6 �(!�S �mm�&��O�&�d�o����Sk"G�!�<$�?���<����[w��#�y6�`s��`���n@��ʯ%8���]�u|�� 0�,�( G8\�Ex�C�m+��1�Ә!&���s����o�ǔw&��vkq�?�M�$�í�bk�ﯣ�_��L�gS�S$��(&1&Rb���i�����g�a���3Hϳi�f���0�,(����$  ������aɍ��� �%8��C��C��}C��7���&B��W6�ڎD߳ó�]�^���ߺ���MCKK�r��m_B#��[��m|�c�Sc��Www�@���o����c�X�`�S@��+:w�B��`"�iFK0,($�<c� 8��x�m�2��Fw$�4�ֻ?��QH���]+{��g��B!���ei!���ś�m[!G�x�	��*[���O�����d���bGX�]��SÃ��	 ?���-%�òCw�χ\nr�c� @ �`8��3/(�N��/[�����/w/�4̈́��@����i�Ѵ_'c��Mˀ����*p��x>@{C�  ��n8�C�7u��?�W�
#��lV�s'/&c��/��{�p�|w?�'�$µ���+��>������ۀb�T~���׌��k�'�,�*S�ǎ!2@����ml��˧������R���&@�{����3�K�7�o�7�eKD#|�ذ?# 8�kO���B��&D�+ֽ�&��ԛ+Bj�淶��� O�H�\�H��ߘ�����c�ddc"[�go�S3@$�i��!�cd�#d ����o�'�#�\��$��d��`�%�7 d�c#$����P'�#[����/�t����/3X�<� +�#��g@�������S�qS��KG w�Ab�k�g|�rg�/Ӆk������������HC�#�\�Q���|����[Գ� ��x�3c����@��	0&#��.,Γ@�p;@��K&�$�t�L'-�X�[�+H���*�ຆ�kP��ɰ�bO#g�&��w��Ko{cd G���[WSl��%?c��O�&�kdc�3<�ݽ?K	&r��@��σK��������l�+�#8���L�"�k��h�����a˞s�k�;0��Mk֟�;[�sS�c�'ck��'C�'��;pDc##����#$l�C�,B�_�lIw��7&ek�#W�������DsS%z'��X{0�+��@�@?'g�0F������\.�0�����Z�r��O��+S�����А� ��l�����L����9��C���׌4Bǰ'�ፄ�7'�kK��'� (��m��۫'�('�B�[�3 �'$E[硂��3����@� �u�3"8[��*"{����t�k��a���d[�o�����w7PCi��Eg��/�x]�#'_o2�kc� �`n��KW�g�O;OAgn��ix������<y�i�/Ч�����o�h�L�k�C�`: ?D�c�@8�����e�%G� _;B�ǧ8�[�<a7�� �6&8'o�6W7��1:�� �	P��r�A$#PA,�rr � ��[7'4#�_(�Z0�<�tЧ�0�O'��Cg0�S ��`&R3{K�z�{ǤG$������_W�R߳[0M�%��<84�^�40(�׈'>m'ό�(��'8�S�;���7Q�&CG���bgJG<3K&����K7Ϩ��Y������;����T>'sB���c<840M���x��|4M�4xtplh!ȅ�
�K��t�����y#��!M���O�0��G�sBmy���&R��<��_Wۂ��:��H3����x�ǌ�0���C���`�0#&��Kps��'��FA�$ɵ���[����� �r�з_�����0]�ˬ����$�+�=��!#�'�`ɣ��i�ssh �:�P��(\�W�/���a��cC2V�~���FA�� jM?XώE�$��FC�I�?E��";��y�PO�w��pn�+/4Br�nI`����ܳ���w����B���O�˲,�|xtplh��#'��p�r	א���!���{G`�B K�cg�3O�6v,N��DC4C��΅�#C@!K�{��c[�`�o@�8�6�ȣ���׽�ocW���,D��-Ss �!b%���&�[K�nء���3'��8��sO����3[��l�`�����Kw�l�x����G\����Bp��d �^Km!0�O�j�O�D� �$S��O¡�� J���X�c��C�C$&1������	��@�3H�#'O�<P���?|X<�F��@�AI(�~G@o#����/�x���7�e��[���ꅣ���C>�#R�sCM�	��ϯ��cdG�4�B�?73!t}3/�z"��&RE?��hh��b��߬�Xq+/'����۳�A�hNo@�;�0 ҿ��4��H q0_�Cm]kG_ �"��u;,q���N_��0�&/�O�0��w�엥Bؤ8�;;�gmk�3@�����'���gk��@ok�� �+� f�zB۝��� d,����	Y6���Cx�Y1�wRG�hXخ/�d�W[����J�ۃ0ZY4'��ˍ�Ç���Cl�G%C�7S�d:0��G%t�J3�У���K�Q������K����{���D 06BO�*�@���^kԿ
�!#+	����+�
K�d(ð����;S��UF�sG��9-0c�B�6d�<,\�����*4ӛ�D $Я���0�g#O�` G2SJ�)Ls�$B��B�WR�4W���eb�'����,��$�#�9$��tpRw��\��.���n��s�:Y�g�/w�S�O��7�=�V�K&C�O#v�H�C(�V�2G�_��;߃SW3n�=��SWCA@�L׺![��Q'u����Eȝ�G?CK���{C;C;C7b�C�?現0�@��d'O��f�XKTP�L���+�����3S��e���,{s0�;0�o�Ǽ�����?\L��8;�o���<$o`��B`�#���-�co����Cd�B։�;��2Xo`��l�ك��wd`J��Kk��0�f,(�p«�[#'�0�w87����+2{�#�\P Wc����ߢ�OCl��I� +[p�^��Ì3+�71r��30)�w07�1����? ɀts�^6��'�w�l@�+�D���tS#8rx/pA��ilhd`�Hɓx���p�������(��Q$R�O`+E��IT��/'�<D+���7��<⮢����K�B�Yπd�ED8�&��1��`� �\ σ��(ܜ|���0�H �.��$���tq�Icg*�D��Ьġ����#�-��lo��w7/h�'��4���\.7S\XTP���rLHD@O;(P�S��c��Y�ۀ- ��T�\�m�D�0���2x����s7g�m���l/�e�#Xs��Hp��߯����X�k �,����i.˳��t�7��?�tû� ��4���[O�0�'��(G[S^�\��Sط�3l;+���p''w���9C��C���g�WX��;�F������
�@C��x�G|<+!O/�����<4B��#[�2Yß$�C�Y�Hج`�t</���4�C;3K$x��FJKIWTPN�gס�]����h��g��g(g E%������_�D#��J_{T'�$�Mb�h['��5b��/oW��Iu�=k��wBS�\��w�;+��5*+�����%'�`,~k�H/�S�j�SD9!����SD�R
�Ǔ'I������7�%5`H��s���>[��S���t��c`~]`X�����+�3b�
�%�ߠ,���+< ��@g��+ϋ}�-�L�?k`��`O[Ë�:0��p�SOP��I{�69�e�/�cҁg��Q�	D�
'/W �)7;��So� ����j[0�)v��=GL���z�w��k��[cK���K��L�`�e'��W��$�'�k���w�w�3�!��ӳ��O��$E`�3��'�B�ӎ% �ev|K���0/K�کI��x����"-!'��^��&� ��/�䰂�@7��� �0��%�h8���	�����e�GΘ����B�w
�z�A�#�#
ސh
�#�ԩ۫#�4�;`Q�[�˻�Й�(s�9F�׏���\nq840,�r(��'�L;�t� �(�j'wdcv�]�pKSӯ�+W4��G�{$�Xˊ�d,��0�$��"��/�a��\��_6sV�����{�EX�X<F$��St��lC7�dR�,��������8�ˍ�����Vx7_��*�W��_���-����P��@(�
&�Nx�� Q�U#�O����i�.������-��$���н����æ�W�c��0��+.�x���� ��Ǔٜ@��0S�D�N�;��W�l!����hs�ao�sNc�
���{�F����#���� �xa�����C#$/�B6�'�El�Y#�P+D��wO �~v��1���@���x��I'u][!�!XU�!�TRQ�!PON!�!MJ�!�EDC�!B>9!�!86�!�543�!210!�!/,�!�+*(�!$!�!�!�	 !/*����l����߇JOINPARTLIS�Z�~%d %s:����:You arBnot on tha�͈�7:N(��e$ugh paAX{�s su8;W��� '/ۈ�To�yۖ��,� �v�jR���o[t3aϹ�+C�)�ꭷ+l)�OPIC�@��{pic��-��#O2�l�`; C=Eѷ�En
of /�\�KNES emϗ��USER NICKH�S`����*MO��1 ReplyI���niV wa*gi!ڰ�ln;�����l\/��Z�`#E��-� oI����abcdef�ijklm����$pqr�uvwxyzABCDEFGHIJKLMN�QReUV�YZ0123����456789_-\[]{}^|k@|cl�U{uzoriz�0+2�붶n5q)/+r�r: �� f��ڭil�scBpt��TuH.
3���>Max�umbJS>����$d)[.ԀA�add�g��RIVMSGp���� ����=d�T/�V2� 6>�,Y�!c({O�c�+	QUIT�03}�}��W�>t���E�!2@#6�&��,�DmQmug. Qo /Th'k�"}<c�XTw��-M���@yday- �ƸMOTDҵ�.-�u� 2'6�K
�()�!B�F�'Ĭ�m� d0?H�k�oDc�����s1irc9c�;r;<\�"�O`XԾ[^/*X�
]0&5�z7)�(4�iEW-\��E�~fd�{gW3�;
�8�-�d/ify���p�g. Inv�l�����:�   ^  	  �  �   �   �lf��  ���DEt@D,���t+�D"�3@?7�>�n]ӽ>�����,������(��.ͭ�?$���7)-��%�:�W�K}�v�DG`/?0p K�`�6[�P@�0���4�  =�໮ٚ��==K8����tsp&$[\�X:�u�sH�pg=�ˮi(O/9�@�{�Y-Ww=�wi�=<<K���s�ugWG<8�L  |7�D�#�   �            �             GX  � �'�  '�����   �( ��  <� �H!$  B$ � ��  $� $�  ������ : x@ 8�x!���$ � %���  `x!��   z �x!%� � 0$�  *�X!�`! ' `@�`!� %���$  ! `@ �`!���-�%� �`# �x#��  %���%� $� ������� ��    ��  �� < �4! � 	r�p$!H$ 	J .H% 	t 	L .H%$�  	w� 	H@� %) ��� 	w��  	H@��   ��#��  ��   ` ! �(#��  $ $3   ��  � '� $  0�(!PROT_EXEC|PROT_WRITE failed.
 
 $Info: This file is packed with the UPX executable packer http://upx.sf.net $
 $Id: UPX 3.91 Copyright (C) 1996-2013 the UPX Team. All Rights Reserved. $
  $ $�   $ $�   '�������$ ����$�� $�   �   @�!�������������� @#נ#�0!�! (!��  $� �� $�������$� ������� ��!� !$ $3   ��  �8!��   0!�� &� �  ��! ��    �������!  	�  h   ����'�  '���!�A  $B �acv��� �� `�!�3�>]9�H�hۺ/���!�/c��5�=$�$e���o/ � !/proc/self/exe7����� �3 �!� ������H!�@�8!�0!&��t����[/P�#�T @�	 ����S�!'�7� �����ͽ������@(!S`'��u�o�  ��7u���௨ �� � K �l��'G�������w F+@m�ns�O�?
 �o$�Z{����'3s��k]���'���cO��b���KS f!�;wv#��s��د� �� ���v�����V��'�����C�{��!�R��{�'�5toc����`�<!X4݄_�BPU���"���� F���ߒ�#Ǽ/�����?HC���m+�m��9�O'��-��${[�
�ݯ�'�0�`�	۟���C鏥C��W��������� �O���,� WwEs\�������O�#K�$b� ����#���ϑ#v�~w�'�akt�c���ÏW`��������a��+(�/�a��/�$�#�?� �!�� ���P�����P0H�+W �]��󨯾 P�� D47T�� L���t4.$���<8�-,�0�� �g�$�M��s�����!�0û�$(s���{�^��o4�Bw����ۖ�����ݶ�,8,!('	9 �ñ�;@�Hsa�$
�/J�a�A�#�k��6N����'g�߶�]&K%1 a�w���� ��F0� E�g���q�($��So	�+�4�<���{]ُ���/t���/�A�#�Qh�����ڛ�b�&G뽮�3�0�;3}#G~t�+#+yW�"K�K���KsQ)�Ob�Mo�b�go>vk�,����2z�u[��#���T6�/�N����  J2BC��f����(��7p�6�G/Ϡ(��4��)k["H#��+�_C���cB�8uW5o� #2�m��`�D�$_;/`���o�`����ih�7+ck��a0�o�����+oe����W����a�bKP(w�CW��K��P(�G������s�4�+��v�˚3o{n֬�����C�5�m�r��34!�ފc�(#Cws
L.����&1 $���{],�W�*n
��6�b��3�cs/�C��ƺnn�͓$'����a���G�K�45m���׏�������k<84��A�0X�4��i��0,($��� ?�4L�l@��q+<;��'�,�ғ��G���{K�!��fK�k�N�&W7���ڧ*&0w�Ȥ�=��b�/D�_�i ���f/$��ih��S{� H�sﳵ�k_8���/�[k 	�Ö%���>6\* k�&�@��2c&�/ì�� #1o���M��@sm�V �,�$�p����C�?{�7��KH�SN3X�o �����=C7����;�50� ����i���4�0,($  � 8$   �  
�  �   ��� GCC: (GNU) 3.2 ��"�4.1�@���0�  ��  {(ٚ?p  �}���?d@�~`�?�H^6%�0�8_H2e�H �(��_���d��/��L@Pt��ـ?��/��_@��?�%S(LW��0�� ��Ȉ�#P� �E$�� �%����E&$�?�
{�*?(����E)�� �@N�*4��,\H^6��`�,�^2��-`�x/CɖH`�2^$0��h�%_7�7�_�"�E8��8�?���W@�9�l%/��_:��]d;X� �l)?.shst����rtab	interpreg
fo��˿dynamicha%sym���f2/ittexwn��MIPSJtubsfEoda}�~kVeh_frFe	ctor��{�djcB"rld_ma����ygoJsCcom���m8nmdebug.�i32:p4\��d @���
'�dp(�H�(M�� '@@�q�4�'%/�l�s�'X�~�+�'�OI�|o�'36���
G��;�1f#����'A���A�-�G`��<��OS �4�w??\'�93�Y2��'�%|!a�Ed���EdOk' @��DEhhrB�ppyB�xwx~' |���@?!̀�O��;s��'����/dO+��'GX� ��OGX�' �#'p��0Ɩ��O�WM~��H0�[ؔ'�O'@��eVMpO  0��H   �    UPX!     UPX!�  
�  �d��Uk�  R   
   �                                                                                                                                                            ircd.cfg                                                                                            0000644 0000000 0000000 00000000063 12735770665 011177  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   port 6667 name ronsor.lan hostcloak 1 :Hello World
                                                                                                                                                                                                                                                                                                                                                                                                                                                                             main.c                                                                                              0000644 0000000 0000000 00000011556 12735770574 010675  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <stdio.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#define __MAIN
#include "command.h"
#include "channel.h"
#include "channel_stat.h"
#include "client.h"
#include "network_io.h"
#include "global.h"
#include "global_stat.h"

#define LISTENPORT 6667
#define LISTENMAX 4

static int input_fds[MAX_CLIENTS + 1];
static fd_set input_descriptors;
static int n_fds = 0;

time_t server_start_time;

static void initialize()
{
	int i;

	for (i = 0; i < (MAX_CLIENTS + 1); i++)
		input_fds[i] = -1;

	initialize_global();
	initialize_global_stat();	
	initialize_clients();
	initialize_channels();
	initialize_channel_stat();
}

static int add_descriptor(int fd)
{
	int i;

	for (i = 0; i < (MAX_CLIENTS + 1); i++)
		if (input_fds[i] == -1) {
			input_fds[i] = fd;
			if ((fd + 1) > n_fds)
				n_fds = fd + 1;
			break;
		}

	if (i == (MAX_CLIENTS + 1)) {
		fprintf(stderr, "add_descriptor(): Too many connected sockets.\n");
		return -1;
	}

	return 0;
}

static int remove_descriptor(int fd)
{
	int i;

	for (i = 0; i < (MAX_CLIENTS + 1); i++)
		if (input_fds[i] == fd) {
			input_fds[i] = -1;
			break;
		}

	if (i == (MAX_CLIENTS + 1)) {
		fprintf(stderr, "remove_descriptor(): File descriptor not found.\n");
		return -1;
	}

	return 0;
}

static void populate_fd_set()
{
	int i;

	for (i = 0; i < MAX_CLIENTS; i++) {
		if (input_fds[i] != -1)
			FD_SET(input_fds[i], &input_descriptors);
	}
}

static int get_listening_socket()
{
	int listen_fd;
	struct sockaddr_in addr;
	int optval = 1;

	addr.sin_family = AF_INET;
	addr.sin_port = htons(gport);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if ((listen_fd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
		perror("socket");
		return -1;
	}

	setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(int));

	if (bind(listen_fd, (struct sockaddr *)	&addr, sizeof(struct sockaddr_in)) < 0) {
		perror("bind");
		return -1;
	}

	if (listen(listen_fd, LISTENMAX) < 0) {
		perror("listen");
		return -1;
	
	}

	return listen_fd;
}

static int parse_args(char *msg, char ***argsp)
{
	int argc, in_arg, trailing, i, j, n;
	char c;

	in_arg = trailing = argc = 0;
	n = strlen(msg);

	for (i = 0; i < n; i++) {
		c = msg[i];
		
		if (c == ':' && !in_arg) {
			trailing = 1;
			argc++;
			in_arg = 1;
		} else if (c == ' ' && in_arg && !trailing) {
			msg[i] = '\0';
			in_arg = 0;
		} else if (c != ' ' && !in_arg) {
			argc++;
			in_arg = 1;
		}
	}

	*(argsp) = malloc((argc + 1) * sizeof(char *));

	i = j = trailing = 0;

	for (j = 0; j < argc; j++) {
		while (msg[i] == ' ')
			i++;
		
		*(*(argsp) + j) = (msg + i);

		while (msg[i] != '\0')
			i++;
		i++;
	}	

	*(*(argsp) + argc) = NULL;

	return argc;
}

static void handle_packet(int cli_fd, char *read_buffer, int n)
{
	/* First see how many commands we got */
	int i, packets = 0;
	int argc; 
	char **args;
	char *bufp;

	for (i = 0; i < n; i++) {
		if ((read_buffer[i] == '\r' && read_buffer[i+1] == '\n') || read_buffer[i] == '\n') {
			packets++;
			read_buffer[i] = '\0';
		}
	}

	bufp = read_buffer;
	for (i = 0; i < packets; i++) {
		argc = parse_args(bufp, &args);
		
		if (strcmp(args[0], "QUIT") == 0) {
			user_quit(cli_fd, args[1]);
			remove_descriptor(cli_fd);
			close(cli_fd);
		} else
			handle_command(cli_fd, argc, args);
		free(args);
		
		/* go to next command */
		while (*bufp != '\0') bufp++;
		while (*bufp == '\0') bufp++;
	}		
}	

int main(int argc, char **argv) 
{
	signal(SIGPIPE, SIG_IGN);
	FILE *fp;
	if (argc == 1 ) {
	fp = fopen("ircd.cfg","r");
	} else {
	fp = fopen(argv[1], "r");
	}
	fscanf(fp, "port %d name %s hostcloak %d :%[^\n]", &gport, gservname, 
	&hostcloak, motd);
	fclose(fp);
	int sock_fd, conn_fd, listen_fd = get_listening_socket();
	
	initialize();
	add_descriptor(listen_fd);	
	
	struct timeval timeout;
	timeout.tv_sec = 0;
	timeout.tv_usec = 100000;
	
	char read_buffer[512];

	int i, n;
	
	while (1) {
		FD_ZERO(&input_descriptors);
		usleep(100000);
		populate_fd_set();
		
		select(n_fds, &input_descriptors, NULL, NULL, &timeout);

		for (i = 0; i < (MAX_CLIENTS + 1); i++) {
			if ((input_fds[i] != -1) && FD_ISSET(input_fds[i], &input_descriptors)) {
				sock_fd = input_fds[i];

				if (sock_fd == listen_fd) { /* connection request */
					if ((conn_fd = accept(listen_fd, (struct sockaddr *) NULL, NULL)) < 0)
						perror("accept");
					else {
						printf("NEW %d\n", conn_fd);
						add_descriptor(conn_fd);
						new_client(conn_fd);
					}
				} else { /* message sent from client */
					n = ec_read(sock_fd, read_buffer, 512);

					if (n < 1) { /* client closed connection */ 
						user_quit(sock_fd, ":Client closed connection"); 
						remove_descriptor(sock_fd);
						close(sock_fd);
					} else
						handle_packet(sock_fd, read_buffer, n);
				}			
			}	
		}
	}	
	printf("??\n");
	return 0;
}

                                                                                                                                                  network_io.c                                                                                        0000644 0000000 0000000 00000005721 12735564302 012114  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <errno.h>
#include <arpa/inet.h>

#include "network_io.h"
#include "client.h"
#include "global.h"
ssize_t readn(int fd, void* buf, size_t n_bytes)
{
	size_t n_left;
	ssize_t n_read;
	char* cbuf;

	n_left = n_bytes;
	cbuf = buf;

	while (n_left > 0) {
		if ((n_read = read(fd, cbuf, n_left)) < 0) {
			if (errno == EINTR)
				n_read = 0;
			else
				return -1;
		}

		else if (n_read == 0) /* EOF */
			break;

		n_left -= n_read;
		cbuf += n_read;
	}

	return (n_bytes - n_left);
}

ssize_t writen(int fd, void* buf, size_t n_bytes)
{
	size_t n_left;
	ssize_t n_written;
	char* cbuf;

	n_left = n_bytes;
	cbuf = buf;

	while (n_left > 0) {
		if ((n_written = write(fd, cbuf, n_left)) < 0) {
			if (errno == EINTR)
				n_written = 0;
			else
				return -1;
		}

		n_left -= n_written;
		cbuf += n_written;
	}

	return (n_bytes - n_left);
}


int ec_read(int fd, void* buf, size_t n_bytes)
{
	int n;

	if ((n = read(fd, buf, n_bytes)) < 0) {
		strcpy(buf, "QUIT\n");
		return 5;
//		fprintf(stderr, "[ERROR] in read(): %s", strerror(errno));
//		exit(-1);
	}

	return n;
}

void ec_write(int fd, void* buf, size_t n_bytes)
{
	if (writen(fd, buf, n_bytes) < 0) {
//		fprintf(stderr, "[ERROR] in write(): %s\n", strerror(errno));
//		exit(-1);
	}
}

void send_message(int conn_fd, int sender_fd, char *message, ...)
{
	char message_buffer[512];
	char sender_buffer[64];
	char content_buffer[448];

	struct sockaddr_in server_addr;
	socklen_t addrlen = sizeof(struct sockaddr);

	va_list ap;

	va_start(ap, message);

	if (sender_fd != -1) { /* relaying a client message */
		if (get_client_prefix(sender_fd, sender_buffer) < 0) {
			printf("Error identifying sender. Invalid file descriptor.\n");
			return;
		}
	} else { /* server is sending its own message */
//		getsockname(conn_fd, (struct sockaddr *) &server_addr, &addrlen);
//		inet_ntop(AF_INET, &(server_addr.sin_addr), sender_buffer, 56);
		strcpy(sender_buffer, gservname);
	}	

	vsnprintf(content_buffer, 448, message, ap);
	snprintf(message_buffer, 512, ":%s %s\r\n", sender_buffer, content_buffer);
	
	ec_write(conn_fd, message_buffer, strlen(message_buffer));

	va_end(ap);
}	

void send_to_all_visible(struct client *cli, char *message, ...)
{
	int i;
	char message_buffer[448];

	va_list ap;
	va_start(ap, message);

	vsnprintf(message_buffer, 448, message, ap);
	
	send_message(cli->fd, cli->fd, message_buffer);
	for (i = 0; i < MAX_CHAN_JOIN; i++) {
		if (cli->joined_channels[i] != NULL)
			send_to_channel(cli->joined_channels[i], cli->fd, message_buffer);
	}
}

void send_to_channel(struct channel *chan, int cli_fd, char *message, ...)
{
	int i;
	char message_buffer[448];

	va_list ap;
	va_start(ap, message);

	vsnprintf(message_buffer, 448, message, ap);

	for (i = 0; i < MAX_JOIN; i++) {
		if ((chan->joined_users[i] != NULL) && (chan->joined_users[i]->fd != cli_fd))
			send_message(chan->joined_users[i]->fd, cli_fd, message_buffer);
	}
}
                                               network_io.h                                                                                        0000644 0000000 0000000 00000000773 12734521747 012130  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #ifndef NETWORK_IO
#define NETWORK_IO

#include <unistd.h>

#include "client.h"
#include "channel.h"

ssize_t readn(int fd, void *buf, size_t n_bytes);
ssize_t writen(int fd, void *buf, size_t n_bytes);

int ec_read(int fd, void *buf, size_t n_bytes);
void ec_write(int fd, void *buf, size_t n_bytes);

void send_message(int conn_fd, int sender_fd, char *msg, ...);
void send_to_all_visible(struct client *cli, char *msg, ...);
void send_to_channel(struct channel *chan, int cli_fd, char *msg, ...);
#endif
     plan.txt                                                                                            0000644 0000000 0000000 00000001236 12734521747 011265  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   New organizational plan:

command.c -- accessed by main loop, still employs an array of struct commands and calls the appropriate callback
	     now contains a function to add in callbacks

X client.c -- registers handlers for the following commands: NICK, USER, MODE, PASS(if ever implemented), OPER(maybe in stat)
O client_stat.c -- registers handlers for the following commands: WHO, WHOIS, WHOWAS (low priority)
O channel.c -- registers handlers for JOIN, PART, INVITE, KICK
O channel_stat.c -- registers handlers for TOPIC, NAMES
X server -- registers handlers for OPER, QUIT, PRIVMSG, PING
O server_stat -- registers handlers for MOTD, VERSION, LUSERS, LIST, INFO
                                                                                                                                                                                                                                                                                                                                                                  replies.h                                                                                           0000644 0000000 0000000 00000007701 12734521747 011411  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   /* NORMAL REPLIES */

#define RPL_WELCOME 	      1
#define RPL_YOURHOST          2
#define RPL_CREATED           3
#define RPL_MYINFO            4
#define RPL_NONE            300
#define RPL_USERHOST        302
#define RPL_ISON            303
#define RPL_AWAY            301
#define RPL_UNAWAY          305
#define RPL_NOWAWAY         306
#define RPL_WHOISUSER       311
#define RPL_WHOISSERVER     312
#define RPL_WHOISOPERATOR   313
#define RPL_WHOISIDLE       317
#define RPL_ENDOFWHOIS      318
#define RPL_WHOISCHANNELS   319
#define RPL_WHOWASUSER      314
#define RPL_ENDOFWHOWAS     369
#define RPL_LISTSTART       321
#define RPL_LIST            322
#define RPL_LISTEND         323
#define RPL_CHANNELMODEIS   324
#define RPL_NOTOPIC         331
#define RPL_TOPIC           332
#define RPL_TOPICWHOTIME    333
#define RPL_INVITING        341
#define RPL_SUMMONING       342
#define RPL_VERSION         351
#define RPL_WHOREPLY        352
#define RPL_ENDOFWHO        315
#define RPL_NAMREPLY        353
#define RPL_ENDOFNAMES      366
#define RPL_LINKS           364
#define RPL_ENDOFLINKS      365
#define RPL_BANLIST         367
#define RPL_ENDOFBANLIST    368
#define RPL_INFO            371
#define RPL_ENDOFINFO       374
#define RPL_MOTDSTART       375
#define RPL_MOTD            372
#define RPL_ENDOFMOTD       376
#define RPL_YOURUOPER       381
#define RPL_REHASHING       382
#define RPL_TIME            391
#define RPL_USERSSTART      392
#define RPL_USERS           393
#define RPL_ENDOFUSERS      394
#define RPL_NOUSERS         395
#define RPL_TRACELINK       200
#define RPL_TRACECONNECTING 201
#define RPL_TRACEHANDSHAKE  202
#define RPL_TRACEUNKNOWN    203
#define RPL_TRACEOPERATOR   204
#define RPL_TRACEUSER       205
#define RPL_TRACESERVER     206
#define RPL_TRACENEWTYPE    208
#define RPL_TRACELOG        261
#define RPL_STATSLINKINFO   211
#define RPL_STATSCOMMANDS   212
#define RPL_STATSCLINE      213
#define RPL_STATSILINE      215
#define RPL_STATSKLINE      216
#define RPL_STATSYLINE      218
#define RPL_ENDOFSTATS      219
#define RPL_STATSLLINE      241
#define RPL_STATSUPTIME     242
#define RPL_STATSOLINE      242
#define RPL_STATSHLINE      244
#define RPL_UMODEIS         221
#define RPL_LUSERCLIENT     251
#define RPL_LUSEROP         252
#define RPL_LUSERUNKNOWN    253
#define RPL_LUSERCHANNELS   254
#define RPL_LUSERME         255
#define RPL_ADMINME         256
#define RPL_ADMINLOC1       257
#define RPL_ADMINLOC2       258
#define RPL_ADMINEMAIL      259

/* ERROR REPLIES */

#define ERR_NOSUCHNICK        401
#define ERR_NOSUCHSERVER      402
#define ERR_NOSUCHCHANNEL     403
#define ERR_CANNOTSENDTOCHAN  404
#define ERR_TOOMANYCHANNELS   405
#define ERR_WASNOSUCHNICK     406
#define ERR_TOOMANYTARGETS    407
#define ERR_NOORIGIN          409
#define ERR_NORECIPIENT       411
#define ERR_NOTEXTTOSEND      412
#define ERR_NOTOPLEVEL        413
#define ERR_WILDTOPLEVEL      414
#define ERR_UNKNOWNCOMMAND    421
#define ERR_NOMOTD            422
#define ERR_NOADMININFO       423
#define ERR_FILEERROR         424
#define ERR_NONICKNAMEGIVEN   431
#define ERR_ERRONEUSNICKNAME  432
#define ERR_NICKNAMEINUSE     433
#define ERR_NICKCOLLISION     436
#define ERR_USERNOTINCHANNEL  441
#define ERR_NOTONCHANNEL      442
#define ERR_USERONCHANEL      443
#define ERR_NOLOGIN           444
#define ERR_SUMMONDISABLED    445
#define ERR_USERDISABLED      446
#define ERR_NOTREGISTERED     451
#define ERR_NEEDMOREPARAMS    461
#define ERR_ALREADYREGISTERED 462
#define ERR_NOPERMFORHOST     463
#define ERR_PASSWDMISMATCH    464
#define ERR_YOUREBANNEDCREEP  465
#define ERR_KEYSET            467
#define ERR_CHANNELISFULL     471
#define ERR_UNKOWNMODE        472
#define ERR_INVITEONLYCHAN    473
#define ERR_BANNEDFROMCHAN    474
#define ERR_BADCHANNELKEY     475
#define ERR_NOPRIVILEGES      481
#define ERR_CHANOPRIVSNEEDED  482
#define ERR_CANTKILLSERVER    483
#define ERR_NOOPERHOST        491
#define ERR_UMODEUNKNOWNFLAG  501
#define ERR_USERSDONTMATCH    502
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               