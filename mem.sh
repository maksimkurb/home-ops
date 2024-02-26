POD_MEM_LIMIT=5294080
#Converting a pod memory limit from bytes to megabytes
POD_MEM_LIMIT_MB=`expr $POD_MEM_LIMIT / 1024 / 1024`

#Calculating the metaspace size
METASPACE_SIZE_MB=`expr $POD_MEM_LIMIT_MB / 5`
echo metaspace=$METASPACE_SIZE_MB

#Calculating the compressed class space size
COMPRESSED_CLASS_SPACE_SIZE_MB=`expr $METASPACE_SIZE_MB / 5`
echo COMPRESS=$COMPRESSED_CLASS_SPACE_SIZE_MB

#Calculating the reserved code cache size
#(not a part of the metaspace but it is easier to get it relatively)
RESERVED_CODE_CACHE_SIZE_MB=`expr $METASPACE_SIZE_MB / 3`
echo "RESERVED_CODE_CACHE_SIZE_MB="$RESERVED_CODE_CACHE_SIZE_MB

#Calculating the reserved code cache size
DIRECT_MEMORY_SIZE_MB=`expr $METASPACE_SIZE_MB / 16`
echo "DIRECT_MEMORY_SIZE_MB="$DIRECT_MEMORY_SIZE_MB

#Calculating the reserved system usage and other purposes
OTHER_USAGE_MB=`expr $POD_MEM_LIMIT_MB / 4`

#Calculating total non heap size
NON_HEAP_SIZE_MB=`expr $METASPACE_SIZE_MB + $RESERVED_CODE_CACHE_SIZE_MB + $DIRECT_MEMORY_SIZE_MB + $OTHER_USAGE_MB`
echo NON_HEAP_SIZE_MB=$NON_HEAP_SIZE_MB

#Calculating the heap size
HEAP_SIZE_MB=`expr $POD_MEM_LIMIT_MB - $NON_HEAP_SIZE_MB`
echo HEAP_SIZE_MB=$HEAP_SIZE_MB
