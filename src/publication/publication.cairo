#[starknet::component]
pub mod PublicationComponent {
    // *************************************************************************
    //                              IMPORTS
    // *************************************************************************
    use core::traits::TryInto;
    use karst::interfaces::IProfile::IProfile;
    use core::option::OptionTrait;
    use starknet::{ContractAddress, get_contract_address, get_caller_address, get_block_timestamp};
    use karst::interfaces::IPublication::IKarstPublications;
    use karst::base::{
        constants::errors::Errors::{NOT_PROFILE_OWNER, UNSUPPORTED_PUB_TYPE, ALREADY_REACTED},
        utils::hubrestricted::HubRestricted::hub_only,
        constants::types::{
            PostParams, Publication, PublicationType, ReferencePubParams, CommentParams,
            RepostParams, Upvote, Downvote
        }
    };

    use karst::profile::profile::ProfileComponent;
    use karst::profile::profile::ProfileComponent::PrivateTrait;


    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    #[storage]
    struct Storage {
        publication: LegacyMap<(ContractAddress, u256), Publication>,
        vote_status: LegacyMap<(ContractAddress, u256), bool>,
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Post: Post,
        CommentCreated: CommentCreated,
        RepostCreated: RepostCreated,
        Upvoted: Upvoted,
        Downvoted: Downvoted
    }

    #[derive(Drop, starknet::Event)]
    pub struct Post {
        post: PostParams,
        publication_id: u256,
        transaction_executor: ContractAddress,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RepostCreated {
        repostParams: RepostParams,
        publication_id: u256,
        transaction_executor: ContractAddress,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CommentCreated {
        commentParams: CommentParams,
        publication_id: u256,
        transaction_executor: ContractAddress,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Upvoted {
        publication_id: u256,
        transaction_executor: ContractAddress,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Downvoted {
        publication_id: u256,
        transaction_executor: ContractAddress,
        block_timestamp: u64,
    }

    // *************************************************************************
    //                              EXTERNAL FUNCTIONS
    // *************************************************************************
    #[embeddable_as(KarstPublication)]
    impl PublicationsImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Profile: ProfileComponent::HasComponent<TContractState>
    > of IKarstPublications<ComponentState<TContractState>> {
        // *************************************************************************
        //                              PUBLISHING FUNCTIONS
        // *************************************************************************
        /// @notice performs post action
        /// @param contentURI uri of the content to be posted
        /// @param profile_address address of profile performing the post action
        fn post(ref self: ComponentState<TContractState>, post_params: PostParams) -> u256 {
            let ref_post_params = post_params.clone();
            let profile_owner: ContractAddress = get_dep_component!(@self, Profile)
                .get_profile(post_params.profile_address)
                .profile_owner;
            assert(profile_owner == get_caller_address(), NOT_PROFILE_OWNER);

            let mut profile_component = get_dep_component_mut!(ref self, Profile);
            let pub_id_assigned = profile_component
                .increment_publication_count(post_params.profile_address);

            let new_post = Publication {
                pointed_profile_address: 0.try_into().unwrap(),
                pointed_pub_id: 0,
                content_URI: post_params.content_URI,
                pub_Type: PublicationType::Post,
                root_profile_address: 0.try_into().unwrap(),
                root_pub_id: 0,
                upvote: 0,
                downvote: 0
            };

            self.publication.write((post_params.profile_address, pub_id_assigned), new_post);
            self
                .emit(
                    Post {
                        post: ref_post_params,
                        publication_id: pub_id_assigned,
                        transaction_executor: post_params.profile_address,
                        block_timestamp: get_block_timestamp(),
                    }
                );
            pub_id_assigned
        }

        /// @notice performs comment action
        /// @param profile_address address of profile performing the comment action
        /// @param reference_pub_type publication type
        /// @param pointed_profile_address profile address comment points too
        /// @param pointed_pub_id ID of initial publication comment points too
        fn comment(
            ref self: ComponentState<TContractState>, comment_params: CommentParams
        ) -> u256 {
            let profile_owner: ContractAddress = get_dep_component!(@self, Profile)
                .get_profile(comment_params.profile_address)
                .profile_owner;
            assert(profile_owner == get_caller_address(), NOT_PROFILE_OWNER);

            let ref_comment_params = comment_params.clone();
            let reference_pub_type = self
                ._as_reference_pub_params(comment_params.reference_pub_type);
            assert(reference_pub_type == PublicationType::Comment, UNSUPPORTED_PUB_TYPE);

            let pub_id_assigned = self
                ._create_reference_publication(
                    comment_params.profile_address,
                    comment_params.content_URI,
                    comment_params.pointed_profile_address,
                    comment_params.pointed_pub_id,
                    reference_pub_type,
                );

            self
                .emit(
                    CommentCreated {
                        commentParams: ref_comment_params,
                        publication_id: pub_id_assigned,
                        transaction_executor: comment_params.profile_address,
                        block_timestamp: get_block_timestamp(),
                    }
                );
            pub_id_assigned
        }

        /// @notice performs the mirror function
        /// @param mirrorParams the MirrorParams struct
        fn repost(ref self: ComponentState<TContractState>, repost_params: RepostParams) -> u256 {
            let profile_owner: ContractAddress = get_dep_component!(@self, Profile)
                .get_profile(repost_params.profile_address)
                .profile_owner;
            assert(profile_owner == get_caller_address(), NOT_PROFILE_OWNER);

            let ref_repostParams = repost_params.clone();
            let publication = self
                .get_publication(
                    repost_params.pointed_profile_address, repost_params.pointed_pub_id
                );

            let pub_id_assigned = self
                ._create_reference_publication(
                    repost_params.profile_address,
                    publication.content_URI,
                    repost_params.pointed_profile_address,
                    repost_params.pointed_pub_id,
                    PublicationType::Repost,
                );

            self
                .emit(
                    RepostCreated {
                        repostParams: ref_repostParams,
                        publication_id: pub_id_assigned,
                        transaction_executor: repost_params.profile_address,
                        block_timestamp: get_block_timestamp(),
                    }
                );

            pub_id_assigned
        }
        /// @notice upvote a post 
        /// @param profile_address address of profile performing the upvote action
        ///  @param pub_id id of the publication to upvote
        /// todo!(gate function)
        fn upvote(
            ref self: ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) {
            let mut publication = self.get_publication(profile_address, pub_id);
            let caller = get_caller_address();
            let has_voted = self.vote_status.read((caller, pub_id));
            let upvote_current_count = publication.upvote + 1;
            assert(has_voted == false, ALREADY_REACTED);
            let updated_publication = Publication {
                pointed_profile_address: publication.pointed_profile_address,
                pointed_pub_id: publication.pointed_pub_id,
                content_URI: publication.content_URI,
                pub_Type: publication.pub_Type,
                root_profile_address: publication.root_profile_address,
                root_pub_id: publication.root_pub_id,
                upvote: upvote_current_count,
                downvote: publication.downvote
            };
            self.vote_status.write((caller, pub_id), true);
            self.publication.write((profile_address, pub_id), updated_publication);

            self
                .emit(
                    Upvoted {
                        publication_id: pub_id,
                        transaction_executor: caller,
                        block_timestamp: get_block_timestamp()
                    }
                )
        }
        // @notice downvote a post 
        // @param profile_address address of profile performing the downvote action
        //  @param pub_id id of the publication to upvote
        /// todo!(gate function)

        fn downvote(
            ref self: ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) {
            let mut publication = self.get_publication(profile_address, pub_id);
            let caller = get_caller_address();
            let has_voted = self.vote_status.read((caller, pub_id));
            let downvote_current_count = publication.downvote + 1;
            assert(has_voted == false, ALREADY_REACTED);
            let updated_publication = Publication {
                pointed_profile_address: publication.pointed_profile_address,
                pointed_pub_id: publication.pointed_pub_id,
                content_URI: publication.content_URI,
                pub_Type: publication.pub_Type,
                root_profile_address: publication.root_profile_address,
                root_pub_id: publication.root_pub_id,
                upvote: publication.upvote,
                downvote: downvote_current_count,
            };
            self.publication.write((profile_address, pub_id), updated_publication);
            self.vote_status.write((caller, pub_id), true);
            self
                .emit(
                    Downvoted {
                        publication_id: pub_id,
                        transaction_executor: caller,
                        block_timestamp: get_block_timestamp()
                    }
                )
        }
        fn collect(ref self: ComponentState<TContractState>, pub_id: u256) -> bool {
            true
        }

        // *************************************************************************
        //                              GETTERS
        // *************************************************************************

        /// @notice gets the publication's content URI
        /// @param profile_address the profile address to be queried
        /// @param pub_id the ID of the publication to be queried
        fn get_publication_content_uri(
            self: @ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) -> ByteArray {
            self._get_content_URI(profile_address, pub_id)
        }

        /// @notice retrieves a publication
        /// @param profile_address the profile address to be queried
        /// @param pub_id_assigned the ID of the publication to be retrieved
        fn get_publication(
            self: @ComponentState<TContractState>,
            profile_address: ContractAddress,
            pub_id_assigned: u256
        ) -> Publication {
            self.publication.read((profile_address, pub_id_assigned))
        }

        /// @notice retrieves a publication type
        /// @param profile_address the profile address to be queried
        /// @param pub_id_assigned the ID of the publication whose type is to be retrieved
        fn get_publication_type(
            self: @ComponentState<TContractState>,
            profile_address: ContractAddress,
            pub_id_assigned: u256
        ) -> PublicationType {
            self._get_publication_type(profile_address, pub_id_assigned)
        }

        /// @notice retrieves a post vote_status
        /// @param pub_id the ID of the publication whose count is to be retrieved
        fn has_user_voted(
            self: @ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) -> bool {
            let status = self.vote_status.read((profile_address, pub_id));
            status
        }

        /// @notice retrieves the upvote count
        /// @param profile_address the the profile address to be queried
        /// @param pub_id the ID of the publication whose count is to be retrieved
        fn get_upvote_count(
            self: @ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) -> u256 {
            let upvote_count = self.get_publication(profile_address, pub_id).upvote;
            upvote_count
        }
        /// @notice retrieves the downvote count
        /// @param profile_address the the profile address to be queried
        /// @param pub_id the ID of the publication whose count is to be retrieved
        fn get_downvote_count(
            self: @ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) -> u256 {
            let downvote_count = self.get_publication(profile_address, pub_id).downvote;
            downvote_count
        }
    }


    // *************************************************************************
    //                            PRIVATE FUNCTIONS
    // *************************************************************************
    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Profile: ProfileComponent::HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        /// @notice fill reference publication
        /// @param profile_address the profile address creating the publication
        /// @param content_URI uri of the publication content
        /// @param pointed_profile_address the profile address being pointed to by this publication
        /// @param pointed_pub_id the ID of the publication being pointed to by this publication
        // @param reference_pub_type reference publication type
        fn _fill_reference_publication(
            ref self: ComponentState<TContractState>,
            profile_address: ContractAddress,
            content_URI: ByteArray,
            pointed_profile_address: ContractAddress,
            pointed_pub_id: u256,
            reference_pub_type: PublicationType,
        ) -> u256 {
            let cloned_reference_pub_type = reference_pub_type.clone();
            let mut profile_instance = get_dep_component_mut!(ref self, Profile);
            let pub_id_assigned = profile_instance.increment_publication_count(profile_address);
            let pointed_pub: Publication = self
                .publication
                .read((pointed_profile_address, pointed_pub_id));

            let mut root_profile_address: ContractAddress = 0.try_into().unwrap();
            let mut root_pub_id: u256 = 0.try_into().unwrap();

            match cloned_reference_pub_type {
                PublicationType::Post => {
                    root_pub_id = 0.try_into().unwrap();
                    root_profile_address = 0.try_into().unwrap();
                },
                PublicationType::Repost |
                PublicationType::Comment => {
                    if (pointed_pub.root_pub_id == 0) {
                        root_pub_id = pointed_pub_id;
                        root_profile_address = pointed_profile_address;
                    } else {
                        root_pub_id = pointed_pub.root_pub_id;
                        root_profile_address = pointed_pub.root_profile_address;
                    }
                },
                PublicationType::Nonexistent => { return 0.try_into().unwrap(); }
            };

            let updated_reference = Publication {
                pointed_profile_address: pointed_profile_address,
                pointed_pub_id: pointed_pub_id,
                content_URI: content_URI,
                pub_Type: reference_pub_type,
                root_pub_id: root_pub_id,
                root_profile_address: root_profile_address,
                upvote: 0,
                downvote: 0
            };

            self.publication.write((profile_address, pub_id_assigned), updated_reference);
            pub_id_assigned
        }

        /// @notice create reference publication
        /// @param profile_address the profile address creating the publication
        /// @param content_URI uri of the publication content
        /// @param pointed_profile_address the profile address being pointed to by this publication
        /// @param pointed_pub_id the ID of the publication being pointed to by this publication
        // @param reference_pub_type reference publication type
        fn _create_reference_publication(
            ref self: ComponentState<TContractState>,
            profile_address: ContractAddress,
            content_URI: ByteArray,
            pointed_profile_address: ContractAddress,
            pointed_pub_id: u256,
            reference_pub_type: PublicationType,
        ) -> u256 {
            self._validate_pointed_pub(pointed_profile_address, pointed_pub_id);

            let pub_id_assigned = self
                ._fill_reference_publication(
                    profile_address,
                    content_URI,
                    pointed_profile_address,
                    pointed_pub_id,
                    reference_pub_type,
                );

            pub_id_assigned
        }

        /// @notice returns the publication type
        // @param reference_pub_type reference publication type
        fn _as_reference_pub_params(
            ref self: ComponentState<TContractState>, reference_pub_type: PublicationType
        ) -> PublicationType {
            match reference_pub_type {
                PublicationType::Comment => PublicationType::Comment,
                _ => PublicationType::Nonexistent,
            }
        }

        /// @notice validates pointed publication
        /// @param profile_address the profile address that created the publication
        /// @param pub_id the publication ID of the publication to be checked
        fn _validate_pointed_pub(
            ref self: ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) {
            let pointedPubType = self._get_publication_type(profile_address, pub_id);
            if pointedPubType == PublicationType::Nonexistent
                || pointedPubType == PublicationType::Repost {
                panic!("invalid pointed publication");
            }
        }

        /// @notice gets the publication type
        /// @param profile_address the profile address that created the publication
        /// @param pub_id_assigned the publication ID of the publication to be queried
        fn _get_publication_type(
            self: @ComponentState<TContractState>,
            profile_address: ContractAddress,
            pub_id_assigned: u256
        ) -> PublicationType {
            let publication: Publication = self
                .publication
                .read((profile_address, pub_id_assigned));
            publication.pub_Type
        }

        /// @notice gets the publication content URI
        /// @param profile_address the profile address that created the publication
        /// @param pub_id the publication ID of the publication to be queried
        fn _get_content_URI(
            self: @ComponentState<TContractState>, profile_address: ContractAddress, pub_id: u256
        ) -> ByteArray {
            let publication: Publication = self.publication.read((profile_address, pub_id));
            let pub_type_option: PublicationType = publication.pub_Type;

            if pub_type_option == PublicationType::Nonexistent {
                return "0";
            }
            if pub_type_option == PublicationType::Repost {
                let pointedPub: Publication = self
                    .publication
                    .read((publication.pointed_profile_address, publication.pointed_pub_id));
                let content_uri: ByteArray = pointedPub.content_URI;
                content_uri
            } else {
                let publication: Publication = self.publication.read((profile_address, pub_id));
                let content_uri: ByteArray = publication.content_URI;
                content_uri
            }
        }
    }
}

