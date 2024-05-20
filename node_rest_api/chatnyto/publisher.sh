#!/usr/bin/zsh

# String setup
# exporter l'ip du serveur
export PUBLIC=`curl icanhazip.com`
# exporter l'adresse du broker
export BROKER="41.82.228.52"
# export BROKER="86.104.72.83"


# void loop
while true
do
   #mqtt pub -t hello -h "41.82.228.52" -m "$USER ,alive on: $PUBLIC `date`" from "Inknyto"    
   
   # who is the topic
   # $BROKER is the broker's ip
   # `who` is the who command's output
   mqtt pub -t who -h $BROKER -m "`who` $PUBLIC `date`" from "Inknyto"    
   # echo "I just said hi, `date`"
   sleep 60
done

