_debug() {
    echo "[DEBUG]: $@" >&2
}

# processes .scc kconf commands of the format: kconf <type> <fragment>
#
# Not only do we process the config, the config is migrated into the source
# tree, along with any special files: hardware.cfg, non-hardware.cfg, required.cfg and optional.cfg
#
# The special files, and type of the fragment are used to generate extra information about the
# kernel configuration fragment that can be used later in an audit phase.
#
kconf() {
    local type=$1
    local frag=$2
    local flags=$3
    local text="kconf $frag # $type"
    local simple_config_name=$(basename ${frag})

    # we have some zero/non-zero return codes that are
    # expected and can't have execution abort
    if [ "$scc_errexit" == "on" ]; then
        set +e
    fi

    _debug "===> fragment: $frag flags: $flags"

    local as_module=""
    eval echo "x$flags" | $grep -q "as_module"
    if [ $? -eq 0 ]; then
        as_module="t"
    fi

    relative_config_name=${frag}
    relative_config_dir=""
    if [ -n "${prefix}" ]; then
        relative_config_name=$(echo ${relative_config_name} | sed "s%${prefix}%%")
        relative_config_dir=$(dirname ${relative_config_name})
        mkdir -p ${outdir}/configs/${cbranch_name}/${relative_config_dir}
    else
        mkdir -p ${outdir}/configs/${cbranch_name}/
    fi

    #echo "copying config: ${simple_config_name} to ${outdir}/configs/${cbranch_name}/${relative_config_dir}" >&2
    echo "b" >> /tmp/debug.txt
    # we could compare the source and dest, and either warn or clobber, but
    # for now, we just clobber
    cp -f "$frag" "${outdir}/configs/${cbranch_name}/${relative_config_dir}"
    local simple_module_overrides_name=""

    # if the kconf was included "as_module", then we copy the fragment to
    # a new name, change all the options to =m and then feed that new fragment
    # name to the rest of the processing
    if [ -n "$as_module" ]; then
        cp -f "$frag" "${outdir}/configs/${cbranch_name}/${relative_config_dir}/override-${simple_config_name}"
        # switch all the options to =m
        sed -i 's/=\by\b/=m/g' "${outdir}/configs/${cbranch_name}/${relative_config_dir}/module-override-${simple_config_name}"
        simple_module_overrides_name=$(basename ${module-override-$frag})
    fi

    # Were there any override statements in the fragment ? These are of the format:
    #   # OVERRIDE:CONFIG_<OPTION_NAME>=$VARIABLE_TO_EVALUATE
    #
    # We will split that into the config option and the "expression" (the variable)
    #  - if the expression evaluates to non-zero (aka "something"), then we create
    #    a fixup that is a sed expression to modify the value later. We could just
    #    do the switch, but that suffers from being hidden and hence hard to debug.
    echo "grep -q '# OVERRIDE:' ${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}" >> /tmp/debug.txt
    overrides=$($grep '# OVERRIDE:' "${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}")
    if [ -n "$overrides" ]; then
        _debug "overrides found: $overrides"

        while IFS= read -r override; do
            _debug "override: $override"
            # extract the override, and create a command from it
            # put that command into a fixup.queue file
            # that fixup.queue file can be run by scc after everything else is processed
            # then we can have annotations conditionally change the final value and not
            # have to maintain two different configuration stacks.

	    # Extract the option name (everything before the first '=')
	    option_name=${override%%=*}

	    # Extract the value (between '=' and first space or '#')
	    rest=${override#*=}
	    option_value=${rest%% *}

	    # Extract the override expression (after 'OVERRIDE:')
	    expression=${override#*OVERRIDE:}

	    # # Remove "OVERRIDE:"
            # cleaned_line="${override#*OVERRIDE:}"
            # # Extract option name
            # option_name=$(echo "$cleaned_line" | $cut -d '=' -f 1)
            # # Extract expression
            # expression=$(echo "$cleaned_line" | $cut -d '=' -f 2)

            _debug "Option: $option_name"
            _debug "Expression: $expression"
            _debug "Module var: $MODULE_OR_Y"

            eval x=$expression

            if [ -n "$x" ]; then
                # _debug "original frag: $frag"
                # for debug purposes. The original fragment where it sits is unmodifed, and
                # and it will be copied back over when this is run again
                cp -f "$frag" "${outdir}/configs/${cbranch_name}/${relative_config_dir}/orig-${simple_config_name}"

                # _debug "x: $x"
                # _debug "sed s/^$option_name=./$option_name=$MODULE_OR_Y/"

                echo "sed s/^$option_name=./$option_name=$MODULE_OR_Y/ -i ${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}" >> ${outdir}/fixups
            fi
        done <<< "$overrides"
    fi

    # if there are any classifiers in the fragment dir, we copy them as well
    frag_dir=$(dirname ${frag})
    # echo "frag dir: ${frag_dir}" >&2
    for c in ${frag_dir}/*.kcf ${frag_dir}/hardware.cfg ${frag_dir}/non-hardware.cfg ${frag_dir}/required.cfg ${frag_dir}/optional.cfg ${frag_dir}/y_or_m_enabled.cfg; do
        local simple_special_name=$(basename ${c})
        if [ -e "${c}" ]; then
            cp -f ${c} "${outdir}/configs/${cbranch_name}/${relative_config_dir}"
            # echo "c: ${c}" >&2
            # echo "relative config dir: ${relative_config_dir}"  >&2
            # echo "cbranch: ${cbranch_name}"  >&2
            # echo "outdir: ${outdir}"  >&2
            # echo "config: ${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_special_name}" >&2
            if [ "${c}" == "${frag_dir}/non-hardware.cfg" ]; then
                echo ${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_special_name} >> ${outdir}/non-hardware_frags.txt
            fi
            if [ "${c}" == "${frag_dir}/hardware.cfg" ]; then
                echo ${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_special_name} >> ${outdir}/hardware_frags.txt
            fi
        fi
    done

    eval echo "configs/${cbranch_name}/${relative_config_dir}/${simple_config_name} \# ${type}" >> "${configqueue}"
    eval echo "\$text" $outfile_append

    if [ -n "$simple_module_overrides_name" ]; then
	eval echo "configs/${cbranch_name}/${relative_config_dir}/${simple_module_overrides_name} \# ${type}" >> "${configqueue}"
	eval echo "\$text" $outfile_append
    fi

    if [ "${type}" == "hardware" ]; then
        echo "${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}" >> ${outdir}/hardware_frags.txt
    fi
    if [ "${type}" == "non-hardware" ]; then
        echo "${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}" >> ${outdir}/non-hardware_frags.txt
    fi
    if [ "${type}" == "required" ]; then
        echo "${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}" >> ${outdir}/required_frags.txt
    fi
    if [ "${type}" == "optional" ]; then
        echo "${outdir}/configs/${cbranch_name}/${relative_config_dir}/${simple_config_name}" >> ${outdir}/optional_frags.txt
    fi

    # restore exit on error to the global state
    if [ "$scc_errexit" == "on" ]; then
        set -e
    fi
}
