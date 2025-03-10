#
# Copyright (c) 2021 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


MODEL_DIR=${MODEL_DIR-$PWD}

if [ ! -e "${MODEL_DIR}/models/image_recognition/pytorch/common/inference.py" ]; then
  echo "Could not find the script of inference.py. Please set environment variable '\${MODEL_DIR}'."
  echo "From which the inference.py exist at the: \${MODEL_DIR}/models/image_recognition/pytorch/common/inference.py"
  exit 1
fi

if [ -z "${DATASET_DIR}" ]; then
  echo "The required environment variable DATASET_DIR has not been set"
  exit 1
fi

if [ ! -d "${DATASET_DIR}" ]; then
  echo "The DATASET_DIR '${DATASET_DIR}' does not exist"
  exit 1
fi

if [ -z "${OUTPUT_DIR}" ]; then
  echo "The required environment variable OUTPUT_DIR has not been set"
  exit 1
fi

# Create the output directory in case it doesn't already exist
mkdir -p ${OUTPUT_DIR}

ARGS=""
PRECISION="fp32"
if [ "$1" == "bf16" ]; then
  ARGS="$ARGS --precision bf16"
  PRECISION="bf16"
  echo "### running bf16 datatype"
elif [ "$1" == "fp32" ]; then
  ARGS="$ARGS --precision fp32"
  echo "### running fp32 datatype"
else
  echo "The specified precision '$1' is unsupported."
  echo "Supported precisions are: fp32 and bf16"
  exit 1
fi

export DNNL_PRIMITIVE_CACHE_CAPACITY=1024
export KMP_BLOCKTIME=1
export KMP_AFFINITY=granularity=fine,compact,1,0

source "${MODEL_DIR}/quickstart/common/utils.sh"
_get_platform_type
MULTI_INSTANCE_ARGS=""
if [[ ${PLATFORM} == "linux" ]]; then
  CORES=`lscpu | grep Core | awk '{print $4}'`
    pip list | grep intel-extension-for-pytorch
    if [[ "$?" == 0 ]]; then
        MULTI_INSTANCE_ARGS=" -m intel_extension_for_pytorch.cpu.launch \
        --use_default_allocator --log_path=${OUTPUT_DIR} --log_file_prefix="wide_resnet101_2_accuracy_log_${PRECISION}""
        # in case IPEX is used, we set ipex arg
        ARGS="${ARGS} --ipex"
        echo "Running using ${ARGS} args ..."
    fi
elif [[ ${PLATFORM} == "windows" ]]; then
  CORES="${NUMBER_OF_PROCESSORS}"
fi

BATCH_SIZE=`expr $CORES \* 4`

python ${MULTI_INSTANCE_ARGS} \
  ${MODEL_DIR}/models/image_recognition/pytorch/common/inference.py \
  --data_path ${DATASET_DIR} \
  --arch wide_resnet101_2 \
  --batch_size $BATCH_SIZE \
  --jit \
  -j 0 \
  $ARGS

wait

if [[ ${PLATFORM} == "linux" ]]; then
  accuracy=$(grep 'Accuracy:' ${OUTPUT_DIR}/wide_resnet101_2_accuracy_log_${PRECISION}_* |sed -e 's/.*Accuracy//;s/[^0-9.]//g')
  echo "wide_resnet101_2;"accuracy";${PRECISION};${BATCH_SIZE};${accuracy}" | tee -a ${OUTPUT_DIR}/summary.log
fi
