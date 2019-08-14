function env_init(){
    if [ -f ./environment.sh ]; then
        source ./environment.sh
    else
        echo "parameter init fail,environment.sh file can not found"
    fi
}
