#!/bin/sh

DOMAIN="ikstream.net"
KEY_FILE="/tmp/public_key.pem"
LOG_PATH="/tmp/dalec"
LOG_FILE="${LOG_PATH}/basic.log"
COLLECT="/usr/bin/dalec"
STATS_SERVER="owrt.sviks.de"

# Retrieve the public key from server for encryption
#
# Returns:
#       key: public key of server for encryption of messages
#
get_key()
{
  key=""
  key_pos="\$2"
  echo "-----BEGIN PUBLIC KEY-----"  > $KEY_FILE
  for i in $(seq 1 3);
  do
    key=$key$(dig $DOMAIN TXT @8.8.8.8 | awk -F \;=\; "/pass$i/ { print $key_pos
  }" | tr -d '"')
  done
  echo "$key" >> $KEY_FILE
  echo "-----END PUBLIC KEY-----" >> $KEY_FILE
}

# collect and retrieve statistical data
#
# Arguments:
#   logfile: path to logfile where data is stored
#
# Returns:
#   statistical data concated
#
get_statistics()
{
  logfile=$1
  echo "$(awk -F = '{print $2}' $logfile | tr '\n' ';')"
}

# Encrypt collected stats and encode them base16
#
# Arguments:
#   stat_data: data collected
#
# Returns:
#   enc_data: encrypted and encoded data
#
encrypt_data()
{
  stat_data="$1"

  enc_data=$(echo $stat_data | openssl rsautl -encrypt -inkey $KEY_FILE -pubin | \
    openssl base64 | \
    hexdump -v -e '/1 "%x"')
  echo "$enc_data"
}

# Generate entropic data from memory technnology devices for salt and pass
#
# Returns:
#       hash of all mtd devices
#
generate_data()
{
  tmp_file='/tmp/gen.data'
  data=$(find /dev/ -name 'mtd?ro')

  for i in $(seq 0 8);
  do
    data_file="/dev/mtd${i}ro"
    if [ -c "$data_file" ]; then
      openssl dgst -sha512 $data_file | awk '{print $2}' >> $tmp_file
    fi
  done

  data=$(openssl dgst -sha512 $tmp_file | awk '{print $2}')
  echo "$data"
  # rm $tmp_file
}

# Generate the ID for the device based on it's available MAC addresses
#
# Returns:
#       hash: the sha512 hash of available MAC-addresses
#
generate_id()
{
  if_list='';
  uid=''

  # TODO replace with find
  for interface in $(ls /sys/class/net/);
  do
    if [ "$interface" != 'lo' ]; then
      if_list="${if_list} $(cat /sys/class/net/$interface/address)"
    fi
  done;

  if_list=$(echo $if_list | tr ' ' '\n' | sort -u)

  for mac in $if_list;
  do
    uid=${uid}$(echo $mac | awk -F: '{print $1 $2 $3 $4 $5 $6}'| openssl dgst -sha512 )
  done

  hash="$(echo $uid | openssl dgst -sha512 | awk '{print $2}')"
  echo $hash
  unset uid
}

# Encrypt the generated id, which is DNS conform and cropped to 32 byte
#
# Returns:
#       enc_id: encrpted, dns conform and cropped id
#
encrypt_id()
{
  mtd="$(find /dev/ -name 'mtd?ro')"
  id="$(generate_id)"
  salt_length=16
  if [ -z "$mtd" ]; then
    key=$(echo $id | tail -c $(( ${#id} - $salt_length )))
    salt=$(echo $id | head -c $salt_length)
  else
    crypt_data="$(generate_data)"
    key="$(echo $crypt_data | tail -c $(( ${#crypt_data} - $salt_length )))"
    salt="$(echo $crypt_data | head -c $salt_length)"
  fi

  echo $(echo $id | openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 100000 \
           -k "$key" -S "$salt" -base64 | \
           sed 's;[+/];;g' | head -c 32)
}

# Calculate the number of splits needed
#
# Arguments:
#   base_data: data to calculate number of splits
#   size: chunk size
#
# Return:
#   splits: number of splits
calc_splits() {
  base_data=$1
  size=$2

  if [ "$(expr ${#base_data} % $size)" -eq 0 ]; then
    splits=$(expr ${#base_data} / $size)
  else
    splits=$(expr $(expr ${#base_data} / $size) + 1)
  fi

  echo "$splits"
}

# split the data into chunks
#
# Arguments:
#   data: data to split in chunks
#
# Returns:
#   chunks: a newline sperated string of 62 byte length
#
chunk_data()
{
  data="$1"

  splits=$(calc_splits "$data" 62)
  # iterate over the data in steps of 62 byte
  for i in $(seq 0 $(expr $splits - 1));
  do
    offset=$(expr 61 '*' "$i")
    chunks="${chunks}$(echo $data | cut -b $(expr 1 + $offset)-$(expr 61 + $offset)) "
  done
  echo "$chunks"
}

# Transmitt enrypted and encoded data to server
#
# Arguments:
#   tdata: transmission ready data
#
transmitt_enc_data()
{
  tdata="$1"
  eid=$(encrypt_id)
  chunked="$(chunk_data $tdata)"
  step=0
  msg_count=1
  msg=""
  nr_msgs=$(calc_splits "$tdata" 180)

  for label in $chunked;
  do
    msg="${msg}$label."
    send=0

    if [ "$step" -eq 2 ]; then
      msg="${msg}${eid}-${msg_count}-${nr_msgs}.$STATS_SERVER"
      dig $msg > /dev/null
      msg_count=$(expr $msg_count + 1)
      step=0
      msg=''
      send=1
      continue
    fi

    step=$(expr $step + 1)
  done

  if [ "$send" -eq 0 ]; then
    msg="${msg}${eid}-${msg_count}-${nr_msgs}.$STATS_SERVER"
    dig $msg > /dev/null
  fi
}

/bin/sh $COLLECT -l "$LOG_PATH"
stats="$(get_statistics $LOG_FILE)"
get_key
enc_stats="$(encrypt_data $stats)"
transmitt_enc_data "$enc_stats"
