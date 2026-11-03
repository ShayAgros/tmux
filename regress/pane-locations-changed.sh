#!/bin/sh

# pane-locations-changed fires once per change, listing only the panes that moved

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -LtestA$$ -f/dev/null"
$TMUX kill-server 2>/dev/null

$TMUX new -d -s a -x 80 -y 50 || exit 1
$TMUX set -g pane-locations-changed \
	'set -gF @fired "#{e|+:#{@fired},1}" ; set -gF @moves "#{hook_moves}"'

# check fired moves command... ("*" skips the moves check)
check() {
	expected_fired=$1
	expected_moves=$2
	shift 2
	$TMUX set -g @fired 0 \; set -g @moves '' || exit 1
	$TMUX "$@" >/dev/null || exit 1
	sleep 0.2
	fired=$($TMUX show -gv @fired)
	moves=$($TMUX show -gv @moves | tr '\t' ' ')
	if [ "$fired" != "$expected_fired" ]; then
		echo "$*: fired $fired, expected $expected_fired"
		exit 1
	fi
	if [ "$expected_moves" != "*" ] && [ "$moves" != "$expected_moves" ]; then
		echo "$*: moves [$moves], expected [$expected_moves]"
		exit 1
	fi
}

check 0 '' splitw -d -t a:0.0
check 1 '%1 a.0.1 a.0.2' splitw -d -t a:0.0
check 1 '%2 a.0.1 a.0.0 %0 a.0.0 a.0.1' swapp -d -s a:0.0 -t a:0.1
check 1 '%0 a.0.1 a.0.0 %1 a.0.2 a.0.1 %2 a.0.0 a.0.2' rotatew -t a:0
check 1 '%1 a.0.1 a.0.0 %2 a.0.2 a.0.1' killp -t a:0.0
check 0 '' neww -d -t a:1
check 1 '%3 a.1.0 a.2.0' neww -d -a -t a:0
check 1 '*' neww -d -b -t a:0
check 1 '*' swapw -d -s a:{start} -t a:{end}
check 1 '*' movew -s a:{end} -t a:9
check 1 '*' movew -r -t a
check 0 '' new -d -s b
check 1 '*' movew -s a:{end} -t b:5
check 1 '*' linkw -s b:5 -t a:7
check 1 '*' unlinkw -t a:7
$TMUX splitw -d -t a:{start} || exit 1
check 1 '*' breakp -d -s a:{start}.0
check 1 '*' joinp -d -s a:{end} -t a:{start}.0
check 0 '' movep -d -s a:{start}.1 -t a:{start}.0
check 1 '*' movep -d -b -s a:{start}.1 -t a:{start}.0
check 1 '*' rename -t b c
check 1 '*' set -g pane-base-index 1
$TMUX set -g renumber-windows on
check 1 '*' killw -t a:{start}
check 1 '*' linkw -d -s c:5 -t a:8
check 0 '' kill-session -t c
$TMUX splitw -d -t a:{start} \; splitw -d -t a:{start} || exit 1
check 1 '*' swapp -d -s a:{start}.1 -t a:{start}.2 \; rotatew -t a:{start}

check 0 '' resizep -t a:{start}.1 -x 10
check 0 '' selectl -t a:{start} tiled
check 0 '' selectp -t a:{start}.2
check 0 '' renamew -t a:{start} x
check 0 '' set -p -t a:{start}.1 @x 1
check 0 '' set -g base-index 1
check 0 '' display -p x

$TMUX splitw -d -b -t a:{start}.1 'sleep 0.5' || exit 1
sleep 0.2
check 0 '' display -p x
sleep 1
fired=$($TMUX show -gv @fired)
[ "$fired" = 1 ] || { echo "pane exit: fired $fired, expected 1"; exit 1; }

$TMUX kill-server 2>/dev/null
exit 0
