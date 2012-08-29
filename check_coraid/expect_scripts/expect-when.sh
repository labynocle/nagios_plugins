#!/bin/sh

# ./expect aoeif statefile cec expect

#This file is part of Nagios Check Coraid.
#
#    Nagios Check Coraid is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    Nagios Check Coraid is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with Nagios Check Coraid.  If not, see <http://www.gnu.org/licenses/>.


aoeif=$1
statefile=$2
cec=$3
expect=$4
shelf=$5


`"$expect" > "$statefile" << WAAcecEOF
spawn "$cec" -s $shelf  "$aoeif"
expect "Escape is Ctrl-e"
send "\r"
expect -re " shelf(.*)>"
send "when\r"
expect -re " shelf(.*)>"
send "\r"
send ""
expect ">>>"
send "q\r"
WAAcecEOF`
