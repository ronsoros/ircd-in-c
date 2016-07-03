#ifndef SERVER_H
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
