+++
title = 'GPGPU on AMD: Vector addition kernel using libhsa'
date = 2024-07-06T15:29:45-04:00
draft = false
+++

## Motivation
The following questions have been on my mind for some time now:

1. Why has AMD not been able to replicate CUDA?
2. Why is there no GPGPU (general purpose gpu) programming stack that works across AMD's entire product portfolio?
3. Why do AMD SDKs typically only work with a few Distros and Kernel versions?
4. If you squint a bit and think of shaders as general purpose computation, what explains the disparity between AMD being able to run shader computation on GPUs out of the box on practically any unixen with OSS drivers while being unable to do the same for CUDA style compute tasks? After all adds and multiplies and the primitives around loading compiled code into the GPU should be the same in either case right?


This series of blog posts will be to get answers to the above questions. We will start small and try to run until we run into unsolveable blockers. Who knows we might get all the way to the end :D

Our technical goals for this exercise are
a. Minimal set of dependencies
b. Depend on a open source stack that can be built and replicated out in the open
c. Run across various linux distros out of the box using bog standard kernels and setups

## Technical choices:

We need to make the following technical choices for the following questions

### Pick tool to compile the users compute kernels
We will use clang since it is widely available and since it has the ability to compile C/C++ to AMD GPU binaries

###### Alternatives considered:
I did start out with the hypothesis that I would try to use GL or Vulkan compute shaders and then use the same codepaths that mesa uses to compile and load GL/Vulkan shader kernels but after a day or two of research I gave up since I do not understand mesa very well. 

### Pick a language that users will write compute tasks in
I picked C since clang supports that very well and since it would be relatively straightforward to see disassembly of compiled C kernel output and try to figure out my missteps.

###### Alternatives considered:
If mesa had panned out as a choice I would have considered using GLSL or some Kernel language that compiles to SPIRV. Though to be honest on some level I have come to appreciate that not having graphics bits leak into the users mental model is a net positive wrt general purpose computation. I also considered sticking with opencl but chose not to since getting opencl working out of the box on a linux distro has been a hit or miss affair over time. 

### Pick a tool to upload and run the compiled kernels
We will use libhsa to upload and run our kernels. libhsa is a userspace library that sits on stop of the amdkfd kernel driver that is both open source and available in standard kernels out of the box on various distros. libhsa appears to be widely available on all the distros I checked so far (debian, ubuntu, archlinux).  

###### Alternatives considered
Considered using mesa to compile and load code but gave up due to my own lack of knowledge about mesa. Also looked at libdrm which has really nice apis to copy code from host to gpu but appears to lack the bits to launch a buffer object copied into memory as a kernel


## Toy problem definition
So lets start with a simple problem and try to use an AMD GPU / APU to solve this. We have two arrays a and b and in the ith position of output we would like to store the addition of ith elements of a and b. The C code for this looks like the following

```C
void add_arrays(int* a, int* b, int* output, int num_elements) {
    for (int i = 0; i < num_elements; i++) {
        output[i] = a[i] + b[i];
    }
}
```


## Solution: Vector Addition on GPU using libhsa as orchestrator for compute tasks

Our GPU kernel looks like this 

```C
__attribute__((visibility("default"), amdgpu_kernel)) void add_arrays(int* input_a, int* input_b, int* output)
{
    int index =  __builtin_amdgcn_workgroup_id_x() * __builtin_amdgcn_workgroup_size_x() + __builtin_amdgcn_workitem_id_x();
    output[index] = input_a[index] + input_b[index];
}
```

We compile this kernel using the equivalent of the following bit of shell commands
```bash
clang -fvisibility=default -target amdgcn-amd-amdhsa -mcpu=gfx1103 -c -O3 kernel.c -o kernel.o
clang -fvisibility=default -target amdgcn-amd-amdhsa -mcpu=gfx1103 -O3 kernel.o -o kernel.co
```


And then we are able to launch this kernel using code that looks like this - 

```c++
int dispatch() {
    uint16_t header =
            (HSA_PACKET_TYPE_KERNEL_DISPATCH << HSA_PACKET_HEADER_TYPE) |
            (1 << HSA_PACKET_HEADER_BARRIER) |
            (HSA_FENCE_SCOPE_SYSTEM << HSA_PACKET_HEADER_ACQUIRE_FENCE_SCOPE) |
            (HSA_FENCE_SCOPE_SYSTEM << HSA_PACKET_HEADER_RELEASE_FENCE_SCOPE);

    // total dimension
    uint16_t dim = 1;
    if (aql_->grid_size_y > 1)
        dim = 2;
    if (aql_->grid_size_z > 1)
        dim = 3;
    aql_->group_segment_size = group_static_size_;
    const uint16_t setup = dim << HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS;
    const uint32_t header32 = header | (setup << 16);

    __atomic_store_n(reinterpret_cast<uint32_t *>(aql_), header32, __ATOMIC_RELEASE);

    hsa_signal_store_relaxed(queue_->doorbell_signal, static_cast<hsa_signal_value_t>(packet_index_));

    return 0;
}

// ... shortened for clarity

    struct alignas(16) args_t {
        int *input_a;
        int *input_b;
        int *output;
    };

    auto device_input_a = (int *) engine.alloc_local(num_elements * sizeof(int));
    auto device_input_b = (int *) engine.alloc_local(num_elements * sizeof(int));
    auto device_output = (int *) engine.alloc_local(num_elements * sizeof(int));

    memcpy(device_input_a, input_a.data(), num_elements * sizeof(int));
    memcpy(device_input_b, input_b.data(), num_elements * sizeof(int));

    args_t args{.input_a = device_input_a, .input_b = device_input_b, .output = device_output};

    Engine::KernelDispatchConfig d_param(
        "kernel.co", // kernel compiled object name,
        "add_arrays.kd", // name of kernel
        {120, 1, 1}, // grid size
        {1, 1, 1}, // workgroup size
        sizeof(args_t)
    );

    rtn = engine.setup_dispatch(&d_param);
    memcpy(engine.kernarg_address(), &args, sizeof(args));
    engine.dispatch();
    
    // Sum of numbers 0..n is n * (n - 1) / 2
    // In our case n = 99 - sum would be 99 * 100 / 2 = 4950
    // Since we have two arrays each that sum up to 4950,
    // we expect the sum of those two arrays to be = 2 * 4950 = 9900
    std::cout << "We expected the sum of 2 * sum (0..99) to be :"
            << (num_elements - 1) * num_elements
            << ". Calculated sum is "
            << std::reduce(device_output, device_output + num_elements, 0)
            << std::endl;
    return 0;
}

```

Code for this is available at https://github.com/deepankarsharma/hansa. 


## Conclusion
In this post we were able to stay true to our technical goals

1. The code above only depends on clang and libhsa-dev
2. Code works on a variety of distros and kernels
3. Code works on both GPUs and APUs
4. Code works with upstream kernels

One thing worth mentioning is that we currently hard code the GPU architecture that the code is being compiled for in the cmake file. Will fix in the near future.

Shout of gratitude to [@blu51899890](https://x.com/blu51899890) who very kindly did not say no when I "volunteered" him to be my mentor through this effort. Thanks for being generous with your time [@blu51899890](https://x.com/blu51899890)!!
